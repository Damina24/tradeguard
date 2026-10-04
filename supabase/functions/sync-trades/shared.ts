// Pure logic for the `sync-trades` Edge Function: windowing, backoff, account eligibility,
// provider-field mapping and the authorization gate.
//
// Split out of `index.ts` deliberately — this module touches neither `Deno.env` nor the
// network, so `sync-trades_test.ts` can exercise every rule without a runtime, credentials or
// a Supabase project. The handler in `index.ts` imports from here and adds only I/O.
//
// Security contract for the function as a whole:
//   * `authorized` requires the service-role bearer. `verify_jwt = true` (config.toml) stops
//     anonymous callers at the platform; this gate stops anyone holding an ordinary user JWT
//     from making us spend MetaAPI allowance on demand.
//   * METAAPI_TOKEN is read from the function's own environment in `index.ts` and is never
//     logged, never returned and never written to a column. Provider error bodies are not
//     propagated either: they can echo account identifiers back, so only status codes are logged.
//   * The function runs with the service role, so it bypasses RLS — which is exactly why every
//     write is scoped by an explicit `account_id` taken from the DATABASE, never from the
//     request body.
//
// Idempotency: `trades` has `unique (user_id, external_id)`, so an upsert on that key cannot
// create a duplicate however often this runs. The cursor only narrows the window; identity is
// always the provider's deal id, never a timestamp.

export interface SyncAccount {
  id: string;
  user_id: string;
  nickname: string;
  metaapi_account_id: string | null;
  is_active: boolean;
}

export interface SyncCursorRow {
  account_id: string;
  last_synced_at: string | null;
  last_external_id: string | null;
  last_run_at: string | null;
  consecutive_failures: number | null;
}

/** First run of an account: bounded back-fill so we cannot pull unbounded history. */
export const INITIAL_SYNC_WINDOW_DAYS = 30;

/** Hard ceiling on any single window, so a reset cursor cannot re-read years. */
export const MAX_WINDOW_DAYS = 90;

/**
 * How far before the watermark we re-read.
 *
 * Brokers finalise a deal in stages — commission or swap can be booked after the close, and a
 * deal moves from open to closed. A strict `>` watermark would miss those restatements, so each
 * run overlaps and lets `external_id` dedupe make the overlap free. Timestamps narrow; ids
 * guarantee.
 */
export const SYNC_OVERLAP_HOURS = 6;

/** Page ceiling per account, so a provider that always says "more" cannot spin forever. */
export const MAX_PAGES_PER_SYNC = 20;

const DAY_MS = 86_400_000;

/** Start of the window for a run: overlap for a returning account, bounded window for a new one. */
export function windowStartMs(lastSyncedAt: string | null, nowMs: number): number {
  if (!lastSyncedAt) return nowMs - INITIAL_SYNC_WINDOW_DAYS * DAY_MS;
  const parsed = Date.parse(lastSyncedAt);
  if (Number.isNaN(parsed)) return nowMs - INITIAL_SYNC_WINDOW_DAYS * DAY_MS;

  const floor = nowMs - MAX_WINDOW_DAYS * DAY_MS;
  return Math.max(parsed - SYNC_OVERLAP_HOURS * 3_600_000, floor);
}

/**
 * Whether this account is due.
 *
 * Backoff stops a dead account consuming the shared MetaAPI allowance every 5 minutes. A brand
 * new account (no `last_run_at`) is always due.
 */
export function isDue(
  lastRunAt: string | null,
  consecutiveFailures: number | null,
  nowMs: number,
): boolean {
  if (!lastRunAt) return true;
  const failures = consecutiveFailures ?? 0;
  if (failures <= 0) return true;
  const parsed = Date.parse(lastRunAt);
  if (Number.isNaN(parsed)) return true;

  const backoffMinutes = Math.min(60, 1 << Math.min(failures - 1, 6));
  return nowMs - parsed >= backoffMinutes * 60_000;
}
/**
 * Filters the accounts a run should touch.
 *
 * Two conditions, both deliberate: the account must be active, and it must actually have a
 * provider link. An account with a null `metaapi_account_id` cannot be synced, and attempting it
 * would burn an API call to rediscover that every five minutes.
 */
export function eligibleAccounts(
  accounts: SyncAccount[],
  cursors: Map<string, SyncCursorRow>,
  nowMs: number,
): SyncAccount[] {
  return accounts.filter((a) => {
    if (!a.is_active) return false;
    if (!a.metaapi_account_id) return false;
    const cursor = cursors.get(a.id);
    return isDue(cursor?.last_run_at ?? null, cursor?.consecutive_failures ?? 0, nowMs);
  });
}

/** Deal id: the only stable identity a provider gives us. Never synthesised from a timestamp. */
export function dealExternalId(deal: Record<string, unknown>): string | null {
  const raw = deal.id ?? deal.ticket ?? deal.dealId ?? deal.positionId ?? deal.ticketId;
  if (raw === null || raw === undefined) return null;
  const s = String(raw).trim();
  return s.length > 0 ? s : null;
}

/** Provider direction, as a word or a signed number. */
export function dealDirection(deal: Record<string, unknown>): 'long' | 'short' | null {
  const raw = deal.type ?? deal.direction ?? deal.side;
  if (raw === null || raw === undefined) return null;
  if (typeof raw === 'number') {
    if (raw > 0) return 'long';
    if (raw < 0) return 'short';
    return null;
  }
  const s = String(raw).trim().toUpperCase();
  if (['BUY', 'LONG', 'B', '1', '+1', 'IN'].includes(s)) return 'long';
  if (['SELL', 'SHORT', 'S', '-1', 'OUT'].includes(s)) return 'short';
  return null;
}

/** Finite number, or null. Guards against `"12.3"`-as-string and NaN reaching Postgres. */
export function num(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/** ISO timestamp, or null. Unparseable provider dates are dropped, never guessed. */
export function isoDate(value: unknown): string | null {
  if (typeof value !== 'string' || value.trim().length === 0) return null;
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? null : new Date(parsed).toISOString();
}

/**
 * Maps a provider deal to a `trades` row, or null when it cannot be trusted.
 *
 * Mirrors `TradeSyncMapper` + `ValueNormalizer` on the client. The duplication across languages
 * is unavoidable (an Edge Function cannot import Dart) and is kept honest by testing both sides
 * against the same rules. A row with no deal id is refused: without one there is nothing to
 * deduplicate on, and storing it risks a double-counted trade.
 */
export function toTradeRow(
  deal: Record<string, unknown>,
  accountId: string,
  userId: string,
): Record<string, unknown> | null {
  const externalId = dealExternalId(deal);
  if (!externalId) return null;

  const direction = dealDirection(deal);
  if (!direction) return null;

  const symbol = String(deal.symbol ?? deal.instrument ?? deal.pair ?? '').trim().toUpperCase();
  if (symbol.length === 0) return null;

  const lots = num(deal.volume ?? deal.lots ?? deal.size ?? deal.quantity);
  // Same plausibility rule as `ValueNormalizer.volume`: a 0 or absurd size is a data fault.
  if (lots === null || lots <= 0 || lots > 10_000) return null;

  const profit = num(deal.profit ?? deal.pnl ?? deal.pl) ?? 0;
  const commission = num(deal.commission ?? deal.fee) ?? 0;
  const swap = num(deal.swap ?? deal.financing) ?? 0;

  return {
    account_id: accountId,
    // `trades.user_id` is NOT NULL (migration 0001) and RLS ownership is derived from it, so it
    // must be written explicitly. It comes from our own broker_accounts row, never the request.
    user_id: userId,
    external_id: externalId,
    symbol,
    direction,
    lots,
    entry: num(deal.openPrice ?? deal.open_price ?? deal.entryPrice),
    exit: num(deal.closePrice ?? deal.close_price ?? deal.exitPrice),
    sl: num(deal.sl ?? deal.stopLoss),
    tp: num(deal.tp ?? deal.takeProfit),
    open_time: isoDate(deal.openTime ?? deal.open_time ?? deal.time),
    close_time: isoDate(deal.closeTime ?? deal.close_time ?? deal.exitTime),
    // Net of costs, matching `TradeRecord.netPnl`: the journal must show what was actually
    // earned, never the gross figure.
    pnl: profit + commission + swap,
    commission,
    swap,
  };
}

/** The next cursor watermark: the newest close/open time actually stored, or `fallback`. */
export function nextWatermark(rows: Record<string, unknown>[], fallbackMs: number): string {
  let newest = 0;
  for (const row of rows) {
    for (const key of ['close_time', 'open_time']) {
      const value = row[key];
      if (typeof value === 'string') {
        const parsed = Date.parse(value);
        if (!Number.isNaN(parsed) && parsed > newest) newest = parsed;
      }
    }
  }
  return new Date(newest > 0 ? newest : fallbackMs).toISOString();
}

/** Provider status → our failure vocabulary. Keeps the handler's branches explicit. */
export function classifyStatus(status: number): 'auth' | 'rateLimit' | 'server' | 'other' {
  if (status === 401 || status === 403) return 'auth';
  if (status === 429) return 'rateLimit';
  if (status >= 500) return 'server';
  return 'other';
}

/**
 * Whether the caller may make us spend MetaAPI allowance on demand.
 *
 * Mirrors `guard-check`'s `authorized` exactly, including the locally-served case: with no key
 * configured there is nothing to compare against, so the host is trusted (that is
 * `supabase functions serve`, never production).
 */
export function authorized(
  header: string | null,
  serviceKey: string | undefined,
): boolean {
  if (!serviceKey) return true;
  if (!header || !header.startsWith('Bearer ')) return false;
  return header.slice('Bearer '.length).trim() === serviceKey;
}
