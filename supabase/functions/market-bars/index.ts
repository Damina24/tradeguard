// market-bars — HTTP (auth), per `docs/BACKEND_SCHEMA.md`.
//
//   POST /functions/v1/market-bars  {symbol, interval} -> {symbol, interval, bars[], as_of}
//
// Fetches OHLC bars for ONE allowlisted symbol/timeframe and caches them in `prices_cache` so the
// replay screen (task 2.6) can chart them. The client NEVER calls TwelveData directly — a
// `--dart-define` key ships inside the APK, where anyone who installs the app can extract it and spend
// our metered allowance from outside our product. The key lives only here.
//
// All policy — the symbol allowlist, the response normalisation, the freshness rule — lives in
// `./shared.ts` so `market-bars_test.ts` can verify it without a runtime. This file adds only I/O.
//
// ── Authorization ─────────────────────────────────────────────────────────────────────────────
// This function is USER-facing: a trader opens the replay and asks for a series. So the gate is the
// same shape as `ai-review`, the opposite of `guard-check` / `sync-trades` which need the SERVICE-role
// bearer because a scheduler has no user session.
//
//   * `verify_jwt = true` (config.toml) makes the platform reject anonymous calls.
//   * We RESOLVE the caller with GoTrue using their own bearer token. No query runs as the caller, and
//     `user_id` is never read from the body — there is no per-user row here to write, because cached
//     bars are public market data (see migration 0008).
//   * The WRITE uses the service role, because migration 0008 revokes every client write to
//     `prices_cache`. The service role bypasses RLS, so the write target is constrained by the
//     ALLOWLIST in shared.ts and by nothing the caller supplied beyond that allowlist.
//
// ── Metred-allowance discipline ─────────────────────────────────────────────────────────────────
// TwelveData bills per call, so the function refuses work rather than spending it freely:
//   * an unserved symbol or interval is a 404 before any network call is made;
//   * a fresh cache row is returned WITHOUT calling the provider at all;
//   * a response that normalises to nothing usable is a failure, and never overwrites good cached
//     bars with an empty array.
//
// ── Secrets ────────────────────────────────────────────────────────────────────────────────────
//   TWELVEDATA_KEY   required — without it the function returns 503 `notConfigured`. It is never
//                    logged and never returned. Provider error bodies are not propagated: a TwelveData
//                    error can echo the key back in its URL, so only the status is logged.
//
// Not covered by `flutter test`: this needs a live Supabase project and a `TWELVEDATA_KEY`. The
// security rules it depends on are unit-tested in `market-bars_test.ts`, the client half in
// `test/replay_repository_test.dart`.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
  BARS_PER_REQUEST,
  classifyStatus,
  isAllowedInterval,
  isStale,
  normaliseBars,
  normaliseSymbol,
} from './shared.ts';
import type { CachedBar, ProviderFailure } from './shared.ts';

const TWELVEDATA_BASE = 'https://api.twelvedata.com/time_series';

/** How old a cached row may be before this function spends a call refreshing it. */
const MAX_CACHE_AGE_MS = 6 * 60 * 60 * 1000;

type AnyRecord = Record<string, unknown>;

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function serviceClient() {
  const key = Deno.env.get('SUPABASE_SERVICE_KEY');
  const url = Deno.env.get('SUPABASE_URL');
  if (!key || !url) throw new Error('SUPABASE_SERVICE_KEY / SUPABASE_URL is not set');
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * The caller's user id, resolved from their own bearer token.
 *
 * `SUPABASE_URL` + the ANON key are used only to ask GoTrue who this token belongs to — no query runs
 * as the caller and nothing is written. Returns null when the token is absent or invalid, which the
 * handler turns into a 401.
 */
async function callerId(authHeader: string | null): Promise<string | null> {
  if (!authHeader || !authHeader.startsWith('Bearer ')) return null;
  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!url || !anonKey) return null;

  try {
    const sb = createClient(url, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await sb.auth.getUser(authHeader.slice('Bearer '.length).trim());
    if (error || !data.user) return null;
    return data.user.id;
  } catch {
    // Never log the header: it is a live bearer token.
    return null;
  }
}

/**
 * One provider response, or a failure classification.
 *
 * The key is read from the environment and used for exactly one query parameter on exactly one request.
 * It is never logged, never returned, and the request URL is never logged either — it embeds the key.
 */
async function fetchBars(
  symbol: string,
  interval: string,
): Promise<{ bars: CachedBar[] } | { failure: ProviderFailure }> {
  const key = Deno.env.get('TWELVEDATA_KEY');
  if (!key) return { failure: 'notConfigured' };

  const url =
    `${TWELVEDATA_BASE}?symbol=${encodeURIComponent(symbol)}` +
    `&interval=${encodeURIComponent(interval)}` +
    `&outputsize=${BARS_PER_REQUEST}&order=asc&apikey=${encodeURIComponent(key)}`;

  let res: Response;
  try {
    res = await fetch(url, { headers: { Accept: 'application/json' } });
  } catch {
    console.error('market-bars: provider unreachable');
    return { failure: 'server' };
  }

  if (!res.ok) {
    // Status only. The body can echo the request URL, which embeds the key.
    console.error('market-bars: provider rejected', res.status);
    return { failure: classifyStatus(res.status) };
  }

  let body: unknown;
  try {
    body = await res.json();
  } catch {
    return { failure: 'malformed' };
  }

  // TwelveData answers 200 with an error OBJECT for a bad symbol (e.g. {code: 404, message: ...}),
  // which is why a "successful" response still has to be normalised rather than trusted.
  const record = body as AnyRecord | null;
  if (record !== null && typeof record === 'object' && !Array.isArray(record) && 'code' in record) {
    return { failure: classifyStatus(Number(record.code) || 500) };
  }

  const bars = normaliseBars(body);
  if (bars === null) return { failure: 'malformed' };
  return { bars };
}

/** Reads the cached row, or null when there is none. */
async function readCache(sb: AnyRecord, symbol: string, interval: string): Promise<AnyRecord | null> {
  const { data, error } = await sb
    .from('prices_cache')
    .select('symbol,timeframe,ohlc,updated_at')
    .eq('symbol', symbol)
    .eq('timeframe', interval)
    .limit(1);
  if (error) {
    console.error('market-bars: cache read failed', error.code);
    return null;
  }
  return ((data ?? []) as AnyRecord[])[0] ?? null;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed' }, 405);

  // The caller must be a real, verified session. Their identity is otherwise irrelevant: cached bars
  // are public market data with no `user_id` column (migration 0008). The check exists to stop an
  // anonymous caller spending our metered TwelveData allowance, not to scope a row — and it happens
  // BEFORE the allowlist and the cache read, so an unauthenticated flood costs us nothing at all.
  const authenticated = await callerId(req.headers.get('Authorization'));
  if (authenticated === null) return json({ ok: false, error: 'Unauthorized' }, 401);

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'Invalid body' }, 400);
  }

  const record = (body ?? {}) as AnyRecord;
  // The allowlist check happens BEFORE any network call, so an unserved symbol costs nothing and
  // cannot be used to probe what this deployment has fetched.
  const symbol = normaliseSymbol(record.symbol);
  if (symbol === null) return json({ ok: false, error: 'Unknown symbol' }, 404);
  if (!isAllowedInterval(record.interval)) {
    return json({ ok: false, error: 'Unknown interval' }, 404);
  }
  const interval = (record.interval as string).trim();

  // deno-lint-ignore no-explicit-any
  let sb: any;
  try {
    sb = serviceClient();
  } catch (err) {
    console.error('market-bars: service client unavailable', String(err));
    return json({ ok: false, error: 'notConfigured' }, 503);
  }

  const nowIso = new Date().toISOString();
  const cached = await readCache(sb, symbol, interval);

  // A fresh cache row answers the request WITHOUT touching TwelveData. A replay is historical, so a
  // recently-cached series replays identically — spending a metered call to change nothing would be
  // the single most expensive no-op available here.
  if (cached !== null) {
    const updatedAt = typeof cached.updated_at === 'string' ? cached.updated_at : null;
    const bars = normaliseBars(cached.ohlc);
    if (!isStale(updatedAt, Date.now(), MAX_CACHE_AGE_MS) && bars !== null) {
      return json({
        ok: true,
        symbol,
        interval,
        bars,
        as_of: updatedAt,
        cached: true,
      });
    }
  }

  const answer = await fetchBars(symbol, interval);
  if ('failure' in answer) {
    // 404 stays "not available" so the client can offer a different symbol; 429 and 5xx are generic,
    // because their cause is our provider account rather than anything the trader did.
    if (answer.failure === 'unknownSymbol') {
      return json({ ok: false, error: 'Unknown symbol' }, 404);
    }
    if (answer.failure === 'notConfigured') {
      return json({ ok: false, error: 'notConfigured' }, 503);
    }
    if (answer.failure === 'rateLimit') {
      return json({ ok: false, error: 'rateLimit' }, 429);
    }
    return json({ ok: false, error: 'server' }, 502);
  }

  const bars = answer.bars;

  // `onConflict: symbol,timeframe` is the primary key, so a refresh REPLACES the row rather than
  // appending a second series for the same pair. This is what makes the function idempotent.
  const { error: writeError } = await sb.from('prices_cache').upsert(
    { symbol, timeframe: interval, ohlc: bars, updated_at: nowIso },
    { onConflict: 'symbol,timeframe' },
  );
  if (writeError) {
    console.error('market-bars: cache write failed', writeError.code);
    return json({ ok: false, error: 'server' }, 500);
  }

  return json({
    ok: true,
    symbol,
    interval,
    bars,
    as_of: nowIso,
    cached: false,
  });
});