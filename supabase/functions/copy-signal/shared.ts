// Pure logic for the `copy-signal` Edge Function: body validation, the riskΓåÆlots math, and the
// guardrail policy (paper default, kill switch, live consent, per-account permission, max-lots
// cap, concurrent cap).
//
// Split out of `index.ts` for the same reason as `ai-review/shared.ts` ΓÇö this module touches
// neither `Deno.env` nor the network, so `copy_signal_test.ts` verifies every rule in CI without
// a runtime and without a Supabase project. `index.ts` imports from here and adds only I/O.
//
// ΓöÇΓöÇ Contract ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
//   Input:  { signal_id, account_ids[], risk_pct, mode: 'paper' | 'live' }
//   Output: { ok, mode, results: [{account_id, mode, lots, risk_pct, status, refusal?, order_id?}] }
//
// ΓöÇΓöÇ Security contract ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
//   * **Paper is the default and live is never inferred.** `normalizeMode` returns 'live' only for
//     the exact string 'live'; anything else ΓÇö absent, misspelled, hostile ΓÇö is paper. The mode
//     that actually runs is decided HERE from the trader's stored consent, not from the request:
//     a body asking for 'live' without `copy_settings.live_consent` is a refusal, never a
//     silent downgrade (a downgrade would make the trader believe an order reached a broker).
//   * **The kill switch blocks everything, paper included.** A trader who slams the switch wants
//     copy trading stopped ΓÇö simulating fills while the switch is on would be a lie of omission.
//   * **Lots are recomputed server-side from server-side equity.** The client's preview uses the
//     identical formula (`TradingMath.lotSize` mirrors `lotSize` below, fixture-tested in both
//     suites), but the value that gets written or ordered never comes from the request body ΓÇö
//     the caller-supplied `risk_pct` is clamped, and equity comes from `equity_snapshots`
//     (fallback: `initial_balance`), so a forged body cannot inflate a position.
//   * **Refusals are per-account and explicit.** `maxLots` refuses rather than silently capping:
//     a size the trader never reviewed is exactly the thing a cap exists to prevent.

export const MODE_PAPER = 'paper';
export const MODE_LIVE = 'live';

/** Client and server agree on these defaults (mirrored by `CopySettings` in Dart). */
export const DEFAULT_MAX_LOTS = 5.0;
export const DEFAULT_MAX_CONCURRENT_FOLLOWS = 5;
export const DEFAULT_RISK_PCT = 1.0;
export const MIN_RISK_PCT = 0.25;
export const MAX_RISK_PCT = 5.0;
export const MAX_ACCOUNTS_PER_REQUEST = 10;

export type Mode = typeof MODE_PAPER | typeof MODE_LIVE;

/** Why one account's follow could not be placed. A closed set ΓÇö the client maps these 1:1. */
export type Refusal =
  | 'killSwitch'
  | 'consentRequired'
  | 'accountDisabled'
  | 'accountMissing'
  | 'maxLots'
  | 'maxConcurrent'
  | 'inactiveSignal'
  | 'invalidSignal'
  | 'noMetaapiLink';

/** The signal facts the policy needs. Only these columns are read (allowlist). */
export interface SignalCtx {
  status: string;
  entry: number;
  sl: number;
  tp1: number;
}

/** The account facts the policy needs. No broker identifiers beyond the opaque MetaAPI id. */
export interface AccountCtx {
  id: string;
  equity: number;
  copyEnabled: boolean;
  metaapiAccountId: string | null;
}

/** The trader's stored copy settings (`copy_settings` row, or defaults when absent). */
export interface SettingsCtx {
  liveConsent: boolean;
  killSwitch: boolean;
  maxLots: number;
  maxConcurrentFollows: number;
}

export const DEFAULT_SETTINGS: SettingsCtx = {
  liveConsent: false,
  killSwitch: false,
  maxLots: DEFAULT_MAX_LOTS,
  maxConcurrentFollows: DEFAULT_MAX_CONCURRENT_FOLLOWS,
};

export interface Evaluation {
  mode: Mode;
  lots: number;
  riskPips: number;
  refusal: Refusal | null;
}

/** A validated request body. */
export interface CopyBody {
  signalId: string;
  accountIds: string[];
  riskPct: number;
  mode: Mode;
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** A uuid, lower-cased, or null. */
export function asUuid(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const t = value.trim().toLowerCase();
  return UUID_RE.test(t) ? t : null;
}

/**
 * Paper unless the body says EXACTLY 'live'. Everything else ΓÇö absent, `LIVE `, `true`, an
 * object ΓÇö is paper. The consent check that would permit live happens in `evaluateAccount`.
 */
export function normalizeMode(raw: unknown): Mode {
  return raw === MODE_LIVE ? MODE_LIVE : MODE_PAPER;
}

/** Finite-or-default, clamped into [MIN_RISK_PCT, MAX_RISK_PCT]. */
export function clampRiskPct(raw: unknown): number {
  const n =
    typeof raw === 'number'
      ? raw
      : typeof raw === 'string' && raw.trim() !== ''
        ? Number(raw)
        : NaN;
  if (!Number.isFinite(n)) return DEFAULT_RISK_PCT;
  if (n < MIN_RISK_PCT) return MIN_RISK_PCT;
  if (n > MAX_RISK_PCT) return MAX_RISK_PCT;
  return Math.round(n * 100) / 100;
}

/**
 * Validates the request body. Returns the cleaned body, or an error string.
 *
 * `risk_pct` is never fatal ΓÇö an out-of-range or garbage value degrades to the clamp/default,
 * because refusing a follow over a slider reading would be a worse outcome than sizing it the
 * way the trader's own settings allow.
 */
export function validateBody(
  raw: unknown,
): { ok: true; body: CopyBody } | { ok: false; error: string } {
  if (typeof raw !== 'object' || raw === null) {
    return { ok: false, error: 'Expected a JSON body.' };
  }
  const r = raw as Record<string, unknown>;

  const signalId = asUuid(r.signal_id);
  if (signalId === null) {
    return { ok: false, error: 'signal_id is required.' };
  }

  if (!Array.isArray(r.account_ids) || r.account_ids.length === 0) {
    return { ok: false, error: 'account_ids must be a non-empty array.' };
  }
  if (r.account_ids.length > MAX_ACCOUNTS_PER_REQUEST) {
    return {
      ok: false,
      error: `account_ids is capped at ${MAX_ACCOUNTS_PER_REQUEST}.`,
    };
  }
  const accountIds: string[] = [];
  for (const entry of r.account_ids) {
    const id = asUuid(entry);
    if (id === null) {
      return { ok: false, error: 'account_ids must contain uuids only.' };
    }
    if (!accountIds.includes(id)) accountIds.push(id);
  }

  return {
    ok: true,
    body: {
      signalId,
      accountIds,
      riskPct: clampRiskPct(r.risk_pct),
      mode: normalizeMode(r.mode),
    },
  };
}

/** Standard-lot pip value. Mirrors `TradingMath.pipValue` exactly. */
export function pipValue(symbol: string): number {
  const s = symbol.toUpperCase();
  if (s.startsWith('XAU')) return 10;
  if (s.includes('JPY')) return 9;
  if (s.startsWith('XAG')) return 50;
  return 10;
}

/**
 * Pips between two prices. Mirrors `TradingMath.pipsBetween`: XAUUSD counts a pip as $0.10
 * (factor 10), JPY pairs as 0.01 (factor 100), everything else as 0.0001 (factor 10000).
 */
export function pipsBetween(symbol: string, from: number, to: number): number {
  const s = symbol.toUpperCase();
  const factor = s.startsWith('XAU')
    ? 10
    : s.includes('JPY')
      ? 100
      : 10000;
  return Math.abs(to - from) * factor;
}

/** Round to 2dp, half away from zero. Dart's `toStringAsFixed(2)` rounds half to even; the
 * parity fixtures in both suites avoid exact .xx5 midpoints where the modes disagree. */
function round2(x: number): number {
  return (Math.sign(x) * Math.round(Math.abs(x) * 100)) / 100;
}

/**
 * Risk-based position size in lots.
 * Mirrors `TradingMath.lotSize`: lots = (balance ├ù riskPct/100) / (stopPips ├ù pipValue), 2dp.
 */
export function lotSize(input: {
  balance: number;
  riskPct: number;
  symbol: string;
  stopPips: number;
}): number {
  const { balance, riskPct, symbol, stopPips } = input;
  if (stopPips <= 0 || balance <= 0 || riskPct <= 0) return 0;
  const riskAmount = balance * (riskPct / 100);
  const perLot = stopPips * pipValue(symbol);
  return round2(riskAmount / perLot);
}

/**
 * Evaluates ONE account against the guardrails. Pure: same inputs ΓåÆ same verdict, on both sides.
 *
 * Check order is deliberate:
 *   1. kill switch ΓÇö blocks everything before any other rule is considered.
 *   2. ownership ΓÇö an account id that is not the caller's is `accountMissing`, identical to an
 *      account that does not exist, so this cannot be used to probe for other traders' ids.
 *   3. signal validity ΓÇö inactive or price-less signals cannot be followed at all.
 *   4. per-account permission ΓÇö `broker_accounts.copy_enabled`, off by default.
 *   5. live consent ΓÇö requested 'live' without stored consent is a refusal, never a downgrade.
 *   6. lots ΓÇö recomputed from server equity; over the cap ΓåÆ refused, not silently capped.
 *   7. MetaAPI link ΓÇö live needs the opaque account id the broker connect flow stored.
 *   8. concurrent cap ΓÇö evaluated per-account as the caller walks its list.
 */
export function evaluateAccount(input: {
  pair: string;
  signal: SignalCtx;
  account: AccountCtx;
  settings: SettingsCtx;
  requestedMode: Mode;
  riskPct: number;
  openFollows: number;
  /** False when the requested id is not one of the caller's accounts (ownership miss). */
  accountExists?: boolean;
}): Evaluation {
  const {
    pair,
    signal,
    account,
    settings,
    requestedMode,
    riskPct,
    openFollows,
    accountExists = true,
  } = input;

  const live = requestedMode === MODE_LIVE;
  const base: Evaluation = { mode: requestedMode, lots: 0, riskPips: 0, refusal: null };

  if (settings.killSwitch) return { ...base, refusal: 'killSwitch' };
  if (!accountExists) return { ...base, refusal: 'accountMissing' };
  if (signal.status !== 'active') return { ...base, refusal: 'inactiveSignal' };

  const riskPips = pipsBetween(pair, signal.entry, signal.sl);
  if (!Number.isFinite(riskPips) || riskPips <= 0) {
    // entry == sl (or unreadable prices): the stop is zero-width and any size is a coin flip
    // with unlimited loss. Refused rather than "sized at maximum".
    return { ...base, riskPips: 0, refusal: 'invalidSignal' };
  }
  if (!account.copyEnabled) return { ...base, riskPips, refusal: 'accountDisabled' };
  if (live && !settings.liveConsent) return { ...base, riskPips, refusal: 'consentRequired' };

  const lots = lotSize({
    balance: account.equity,
    riskPct,
    symbol: pair,
    stopPips: riskPips,
  });
  if (lots <= 0) return { ...base, riskPips, refusal: 'invalidSignal' };
  if (lots > settings.maxLots) {
    // Refused, not clamped: the sheet previewed an exact size, and a broker order at a size the
    // trader did not review is the failure mode the cap exists to prevent.
    return { ...base, riskPips, lots, refusal: 'maxLots' };
  }
  if (live && (account.metaapiAccountId ?? '').length === 0) {
    return { ...base, riskPips, lots, refusal: 'noMetaapiLink' };
  }
  if (openFollows >= settings.maxConcurrentFollows) {
    return { ...base, riskPips, lots, refusal: 'maxConcurrent' };
  }

  return { mode: requestedMode, lots, riskPips, refusal: null };
}
