// Pure policy for the `sync-account-data` Edge Function: connection mapping and
// position normalisation.
//
// Split out of `index.ts` so the rules can be unit-tested with no runtime, no
// Supabase project and no MetaAPI credentials — the same discipline `sync-trades`
// and `market-bars` follow.
//
// The function is USER-facing (a trader opens the Guard dashboard), so the gate
// is the GoTrue shape used by `ai-review` / `market-bars`, NOT the service-role
// gate `guard-check` / `sync-trades` use for cron. The `account_id` in the body
// is only ever used to SELECT the caller's own row; the `metaapi_account_id`
// that MetaAPI is called with comes from the DATABASE, never from the request.

export type ConnectionState = 'connected' | 'syncing' | 'offline';

export interface Position {
  id: string;
  symbol: string;
  /** 'buy' or 'sell'. */
  side: 'buy' | 'sell';
  lots: number;
  open_price: number;
  current_price: number;
  pnl: number;
}

/**
 * MetaAPI connection status → our closed [ConnectionState] set.
 *
 * MetaAPI reports a rich status (`CONNECTED`, `CONNECTING`, `DISCONNECTED`,
 * `DISCONNECTED_FROM_BROKER`, `SYNCHRONIZED`, `NOT_AUTHENTICATED`, …). We collapse
 * it to three states the UI can colour bluntly: anything still negotiating is
 * `syncing` (amber), a settled live link is `connected` (green), and everything
 * else — including unknown/absent — is `offline` (red). Nothing is painted green
 * unless MetaAPI actually says the link is up.
 */
export function mapConnection(status: unknown): ConnectionState {
  if (typeof status !== 'string') return 'offline';
  const s = status.trim().toUpperCase();
  if (s === 'CONNECTED' || s === 'SYNCHRONIZED') return 'connected';
  if (
    s === 'CONNECTING' ||
    s === 'SYNCHRONING' ||
    s === 'DEPLOYING' ||
    s === 'UNDEPLOYING'
  ) {
    return 'syncing';
  }
  return 'offline';
}

/** Direction as a word, a numeric string, or the MetaAPI POSITION_TYPE enum. */
function side(raw: unknown): 'buy' | 'sell' | null {
  if (raw === null || raw === undefined) return null;
  if (typeof raw === 'number') {
    // MetaAPI POSITION_TYPE enum: POSITION_TYPE_BUY = 0, POSITION_TYPE_SELL = 1.
    // (Unlike a deal, a position's type is an enum, not a sign, so 0 is BUY here.)
    if (raw === 0) return 'buy';
    if (raw === 1) return 'sell';
    return null;
  }
  const s = String(raw).trim().toUpperCase();
  if (['BUY', 'LONG', 'B', '0'].includes(s)) return 'buy';
  if (['SELL', 'SHORT', 'S', '1'].includes(s)) return 'sell';
  return null;
}

/** Finite number, or null. Same guard as `sync-trades`' `num`. */
function num(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/**
 * Maps one raw MetaAPI position to our [Position], or null when it cannot be
 * trusted.
 *
 * A position with no id, no symbol, no side, or a non-positive size is dropped
 * rather than shown with invented fields — the same "one bad record must not cost
 * the trader the rest" rule `sync-trades` applies to deals. P&L defaults to 0 when
 * absent (a flat position is legitimate); prices default to 0 only as a last
 * resort so a readable row is never blocked by one missing quote.
 */
export function toPosition(raw: Record<string, unknown>): Position | null {
  const id = raw.id ?? raw.positionId ?? raw.ticket;
  if (id === null || id === undefined) return null;

  const symbol = String(raw.symbol ?? raw.instrument ?? '').trim().toUpperCase();
  if (symbol.length === 0) return null;

  const s = side(raw.type ?? raw.side ?? raw.direction);
  if (s === null) return null;

  const lots = num(raw.volume ?? raw.lots ?? raw.size);
  if (lots === null || lots <= 0) return null;

  return {
    id: String(id),
    symbol,
    side: s,
    lots,
    open_price: num(raw.openPrice ?? raw.open_price ?? raw.price) ?? 0,
    current_price:
      num(raw.currentPrice ?? raw.current_price ?? raw.currentTickValue) ?? 0,
    pnl: num(raw.profit ?? raw.pnl ?? raw.swap ?? raw.unrealizedProfit) ?? 0,
  };
}

/** Normalises a MetaAPI `/positions` body into a list of [Position]s. */
export function normalisePositions(body: unknown): Position[] {
  const raw = Array.isArray(body)
    ? body
    : ((body as Record<string, unknown>)?.positions ??
      (body as Record<string, unknown>)?.items);
  if (!Array.isArray(raw)) return [];

  const out: Position[] = [];
  for (const entry of raw) {
    if (entry && typeof entry === 'object' && !Array.isArray(entry)) {
      const p = toPosition(entry as Record<string, unknown>);
      if (p) out.push(p);
    }
  }
  return out;
}

// ── Daily rate limit (MetaAPI credit protection) ──────────────────────────────
//
// MetaAPI is metered and `sync-account-data` is on demand, so a single user mashing refresh (or a
// script replaying the endpoint with their own JWT) could exhaust the shared allowance. We cap the
// number of live syncs one user may make per UTC day. The count lives in the `api_rate_limits`
// table (migration 0011) and is advanced atomically by the `consume_sync_quota` RPC; this file
// holds only the constants and the pure decision, so the cap and the trader-facing message are
// unit-tested without a runtime or a Supabase project.

/**
 * Maximum live-data syncs a single user may make per UTC day.
 *
 * Chosen to leave generous headroom for a trader refreshing the Guard dashboard throughout the
 * day while still capping a runaway loop or an automated replay. It is a product knob, not a
 * security boundary on its own — the atomic RPC is what enforces it.
 */
export const DAILY_SYNC_LIMIT = 60;

/**
 * The exact trader-facing message returned when the daily cap is reached.
 *
 * Wording is fixed here (and mirrored on the client) so the wording never drifts. It names no
 * internal detail — not the table, not the count, not "MetaAPI".
 */
export const DAILY_SYNC_LIMIT_MESSAGE =
  'Daily sync limit reached. Please try again tomorrow.';

/**
 * Whether the result of `consume_sync_quota` means the user is out of quota.
 *
 * The RPC returns the new count (>= 1) when a credit was consumed, or 0 when the user is already
 * at the cap for today. Anything non-positive (including a null/undefined from a mis-shaped call)
 * is treated as "exhausted" so the caller fails safe and never spends a MetaAPI credit it has not
 * paid for.
 */
export function quotaExhausted(count: number | null | undefined): boolean {
  return !Number.isFinite(count as number) || (count as number) <= 0;
}
