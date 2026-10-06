// Pure logic for the `market-bars` Edge Function: the symbol allowlist, the provider-response
// normalisation, freshness and the output caps.
//
// Split out of `index.ts` for the same reason as `ai-review/shared.ts` — this module touches neither
// `Deno.env` nor the network, so `market-bars_test.ts` can verify every rule in CI without a runtime,
// without `TWELVEDATA_KEY` and without a Supabase project. `index.ts` imports from here and adds only
// I/O.
//
// ── Security contract ───────────────────────────────────────────────────────────────────────────
//   * `TWELVEDATA_KEY` lives only in the function's environment. It is never logged, never returned
//     and never written to a column. Upstream error bodies are not propagated either: a TwelveData
//     error can echo the key back in a URL, so only status codes are logged.
//   * **The symbol is an ALLOWLIST, not a blacklist.** The endpoint is metered per call, so an open
//     symbol field would let any signed-in user spend our allowance on an arbitrary instrument — and
//     would let them probe what this deployment has fetched. `isAllowedSymbol` is the enforcement and
//     `ALLOWED_SYMBOLS` is what a future edit must extend deliberately.
//   * The interval is a closed set for the same reason: a free-text timeframe is a value the function
//     would have to sanitise before spending a call on it.
//   * The function writes with the service role (RLS bypassed), so migration 0008 revokes every client
//     write to `prices_cache`, and this module never accepts a caller-supplied row.

/** The only symbols this deployment will fetch. Mirrors `MockPriceBarRepository.defaultSeries`. */
export const ALLOWED_SYMBOLS = ['XAUUSD', 'EURUSD', 'GBPUSD', 'USDJPY', 'US30'] as const;

/** The only intervals this deployment will fetch. Mirrors `ReplayTimeframe`. */
export const ALLOWED_INTERVALS = ['15min', '1h', '4h', '1day'] as const;

export type AllowedSymbol = (typeof ALLOWED_SYMBOLS)[number];
export type AllowedInterval = (typeof ALLOWED_INTERVALS)[number];

/**
 * Bars per request.
 *
 * 500 is TwelveData's practical ceiling on a free key, and it is also enough for a scan to clear its
 * reporting floor: the client needs at least 10 resolved trades out of the series.
 */
export const BARS_PER_REQUEST = 500;

/** Cap on bars written per row, so a hostile or broken response cannot balloon the cache row. */
export const MAX_BARS_PER_SERIES = 500;

/** A provider failure. Never a raw status or body. */
export type ProviderFailure =
  | 'notConfigured'
  | 'rateLimit'
  | 'server'
  | 'unknownSymbol'
  | 'malformed';

/** One bar in the `prices_cache.ohlc` shape. Short keys: a 500-bar series is hundreds of KB. */
export interface CachedBar {
  t: string;
  o: number;
  h: number;
  l: number;
  c: number;
}

/** Normalises a symbol, or false when it is not on the allowlist. */
export function isAllowedSymbol(value: unknown): boolean {
  if (typeof value !== 'string') return false;
  const symbol = value.trim().toUpperCase();
  return (ALLOWED_SYMBOLS as readonly string[]).includes(symbol);
}

/** Normalises a symbol to its canonical form, or null when it is not allowed. */
export function normaliseSymbol(value: unknown): string | null {
  return isAllowedSymbol(value) ? (value as string).trim().toUpperCase() : null;
}

/**
 * Maps our canonical cache symbol to the TwelveData wire symbol.
 *
 * TwelveData requires a slash for forex/metals (docs example: `EUR/USD`),
 * so `EURUSD` -> `EUR/USD`, `XAUUSD` -> `XAU/USD`, etc. Cache key stays
 * canonical; only the provider request uses the mapped form.
 */
export function providerSymbol(symbol: string): string {
  const map: Record<string, string> = {
    'XAUUSD': 'XAU/USD',
    'EURUSD': 'EUR/USD',
    'GBPUSD': 'GBP/USD',
    'USDJPY': 'USD/JPY',
    'US30': 'DJI',
  };
  return map[symbol] ?? symbol;
}

/** True when the interval is one this deployment will fetch. */
export function isAllowedInterval(value: unknown): boolean {
  return normaliseInterval(value) !== null;
}

/**
 * Normalises a timeframe/interval to its canonical TwelveData wire value,
 * or null when it is not allowed.
 *
 * Accepts both `interval` and `timeframe` key names (callers mix them),
 * trims whitespace, is case-insensitive, and maps common aliases
 * (`1H`, `1hour`, `60min`, `H1`, `1D`, `daily`, …) to the canonical set.
 * This is the exact fix for `{"symbol":"EURUSD","interval":"1h"}`
 * returning 404 `Unknown interval` when sent as `1H` / `timeframe`.
 */
export function normaliseInterval(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const v = value.trim().toLowerCase();
  const aliases: Record<string, string> = {
    '15min': '15min',
    '15m': '15min',
    '1h': '1h',
    '60min': '1h',
    '60m': '1h',
    'h1': '1h',
    '1hour': '1h',
    '1hr': '1h',
    '4h': '4h',
    'h4': '4h',
    '240min': '4h',
    '240m': '4h',
    '4hour': '4h',
    '1day': '1day',
    '1d': '1day',
    'd1': '1day',
    'daily': '1day',
  };
  const canonical = aliases[v] ?? v;
  return (ALLOWED_INTERVALS as readonly string[]).includes(canonical)
    ? canonical
    : null;
}

/**
 * Turns whatever TwelveData returned into storable bars, oldest first.
 *
 * Returns null only when there is nothing usable at all — that is a failed call, and the caller must
 * not cache an empty array, because doing so would overwrite good cached bars with nothing and the
 * replay would lose history it already had.
 *
 * Three normalisations matter:
 *   * **Sorted oldest first.** TwelveData answers newest-first and the client walks forward in time.
 *     Replaying a reversed series would fill at a price that had not happened yet.
 *   * **Deduplicated by timestamp, last write wins.** A provider restating a bar is corrected rather
 *     than doubled; one timestamp is not two bars.
 *   * **Malformed rows dropped, not fatal.** One odd record must not cost the trader the other 499. A
 *     bar whose high is below its low is refused, because rendering it would draw a chart the market
 *     cannot have produced.
 */
export function normaliseBars(raw: unknown): CachedBar[] | null {
  const container = raw as Record<string, unknown> | null;
  const values = Array.isArray(raw)
    ? raw
    : container !== null && typeof container === 'object'
      ? container.values ?? container.bars
      : undefined;

  if (!Array.isArray(values)) return null;

  const byTime = new Map<string, CachedBar>();
  for (const entry of values) {
    const bar = toBar(entry);
    if (bar !== null) byTime.set(bar.t, bar);
  }
  if (byTime.size === 0) return null;

  const bars = [...byTime.values()].sort((a, b) => Date.parse(a.t) - Date.parse(b.t));
  // Truncate from the FRONT so the most recent bars survive: a replay of the recent past is far more
  // useful than one that kept the oldest window and discarded everything since.
  return bars.length > MAX_BARS_PER_SERIES ? bars.slice(bars.length - MAX_BARS_PER_SERIES) : bars;
}

/** Parses one provider row, in either the object or the positional-tuple form. */
function toBar(entry: unknown): CachedBar | null {
  if (Array.isArray(entry)) {
    if (entry.length < 5) return null;
    return build(entry[0], entry[1], entry[2], entry[3], entry[4]);
  }
  if (entry !== null && typeof entry === 'object') {
    const row = entry as Record<string, unknown>;
    return build(
      row.datetime ?? row.t,
      row.open ?? row.o,
      row.high ?? row.h,
      row.low ?? row.l,
      row.close ?? row.c,
    );
  }
  return null;
}

function build(t: unknown, o: unknown, h: unknown, l: unknown, c: unknown): CachedBar | null {
  const iso = isoDate(t);
  if (iso === null) return null;
  const open = num(o);
  const high = num(h);
  const low = num(l);
  const close = num(c);
  if (open === null || high === null || low === null || close === null) return null;
  if (high < Math.max(open, close) || low > Math.min(open, close)) return null;
  return { t: iso, o: open, h: high, l: low, c: close };
}

/**
 * Whether a cached row is too old to trust for a replay.
 *
 * Deliberately generous. A replay is historical by nature: a six-hour-old H1 series replays
 * identically to a two-minute-old one, so re-fetching it would burn metered allowance to change
 * nothing. TwelveData also serves D1 bars that only update once a day.
 */
export function isStale(updatedAtIso: string | null, nowMs: number, maxAgeMs: number): boolean {
  if (!updatedAtIso) return true;
  const parsed = Date.parse(updatedAtIso);
  // An unparseable stamp counts as stale, not fresh: a row whose age cannot be established is not one
  // to present as current.
  if (Number.isNaN(parsed)) return true;
  return nowMs - parsed > maxAgeMs;
}

/** Provider status → our failure vocabulary. Keeps the handler's branches explicit. */
export function classifyStatus(status: number): ProviderFailure {
  if (status === 404) return 'unknownSymbol';
  if (status === 429) return 'rateLimit';
  return 'server';
}

/** Finite number or null. Never NaN, never Infinity — either would poison every R downstream. */
function num(value: unknown): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value !== 'string' || value.trim().length === 0) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

/**
 * A timestamp as ISO-8601 in UTC, or null.
 *
 * Two shapes are handled, and the second one matters more than it looks:
 *
 *  1. TwelveData sends `2024-01-02T00:00:00`, a bare `2024-01-02` for daily bars, and a Unix epoch
 *     string for some intraday intervals. All three are accepted — refusing a daily bar over a missing
 *     `T00:00:00` would silently drop the series a trader most often wants to replay.
 *  2. **Those naive timestamps carry no zone, and `new Date('2024-01-02T00:00:00')` reads them as
 *     LOCAL time.** On any device that is not on UTC that silently shifts every bar — and since the
 *     normalised bars are written to a SHARED `prices_cache` row, two users in different zones would
 *     then replay different series for the same symbol and interval, and neither would be
 *     reproducible. A naive timestamp is therefore pinned to UTC here, so the cache holds one
 *     canonical answer regardless of where the fetch was served from.
 */
function isoDate(value: unknown): string | null {
  if (typeof value !== 'string' || value.trim().length === 0) return null;
  const raw = value.trim();

  // Bare epoch seconds (10 digits or more).
  if (/^\d{9,}$/.test(raw)) {
    const fromEpoch = new Date(Number(raw) * 1000);
    return Number.isNaN(fromEpoch.getTime()) ? null : fromEpoch.toISOString();
  }

  // No zone designator at all → pin to UTC. A trailing `Z` or a `±HH:MM` offset is left alone,
  // because the provider was explicit and we should not second-guess it.
  const hasZone = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(raw);
  const candidate = hasZone ? raw : `${raw}Z`;
  const parsed = new Date(candidate);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}