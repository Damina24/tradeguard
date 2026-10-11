// sync-account-data — HTTP (auth), per `docs/BACKEND_SCHEMA.md`.
//
//   POST /functions/v1/sync-account-data  {account_id} ->
//     {ok, account_id, balance, equity, connection, linked, positions[], as_of}
//
// Live read for the Guard dashboard: balance, equity, connection health and the
// currently open positions for ONE of the caller's own broker accounts. The client
// never calls MetaAPI directly — `METAAPI_TOKEN` lives only in this function's
// environment, and only the opaque `account_id` crosses the wire.
//
// ── Authorization ──────────────────────────────────────────────────────────────
// USER-facing, not cron: a trader opens the dashboard. Same gate shape as
// `ai-review` / `market-bars`:
//   * `verify_jwt = true` (config.toml) makes the platform reject anonymous calls.
//   * We RESOLVE the caller with GoTrue from their own bearer token, then read the
//     `broker_accounts` row with the service role and filter by BOTH the resolved
//     `user_id` AND the requested `account_id`. Ownership is part of the WHERE, so
//     another trader's account simply is not returned (a 404, identical to one that
//     does not exist — this endpoint cannot be used to probe for account ids).
//   * `metaapi_account_id` comes from the DATABASE, never from the body. The body's
//     `account_id` only ever selects the caller's own row.
//
// ── Secrets ────────────────────────────────────────────────────────────────────
//   METAAPI_TOKEN   required — without it the function returns 503 `notConfigured`
//                   and the client shows a grey "not linked" state, never a red one.
//                   It is never logged and never returned. Provider error bodies are
//                   not propagated: a MetaAPI error can echo the account id back, so
//                   only the status code is logged.
//
// Not covered by `flutter test`: needs a live Supabase project + MetaAPI token. The
// connection-mapping and position rules are unit-tested in `sync-account-data_test.ts`.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import { mapConnection, normalisePositions } from './shared.ts';
import type { ConnectionState, Position } from './shared.ts';

const METAAPI_BASE = 'https://api.metavantage.com';

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
 * Mirrors `ai-review`'s `callerId`: the anon key + the caller's token ask GoTrue
 * who this is. No query runs as the caller and nothing is written here.
 */
async function callerId(authHeader: string | null): Promise<string | null> {
  if (!authHeader || !authHeader.startsWith('Bearer ')) return null;
  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!url || !anonKey) return null;

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await userClient.auth.getUser();
  if (error) return null;
  const id = data?.user?.id;
  return typeof id === 'string' && id.length > 0 ? id : null;
}

/** A uuid, or null. Anything else is a bad request rather than a query. */
function accountIdFrom(body: unknown): string | null {
  if (typeof body !== 'object' || body === null) return null;
  const id = (body as AnyRecord).account_id;
  if (typeof id !== 'string') return null;
  const trimmed = id.trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(trimmed)) {
    return null;
  }
  return trimmed.toLowerCase();
}

/**
 * Account info + open positions from MetaAPI, or a failure classification.
 *
 * The token is read from the environment and used for exactly one header per
 * request; it is never logged and never returned. A non-2xx logs the STATUS ONLY:
 * a MetaAPI error body can echo the account identifier back. Account info is best
 * effort — a missing `equity` degrades to `offline` with zeros rather than failing
 * the whole read, because the dashboard can still show "no live data" honestly.
 */
async function fetchAccount(
  providerAccountId: string,
): Promise<
  | { balance: number; equity: number; connection: ConnectionState; positions: Position[] }
  | { failure: string }
> {
  const token = Deno.env.get('METAAPI_TOKEN');
  if (!token) return { failure: 'notConfigured' };

  const headers = { Authorization: `Bearer ${token}`, Accept: 'application/json' };

  // Account info (balance, equity, connection status).
  let info: AnyRecord | null = null;
  try {
    const res = await fetch(
      `${METAAPI_BASE}/v3/accounts/${encodeURIComponent(providerAccountId)}`,
      { headers },
    );
    if (res.status === 401 || res.status === 403) return { failure: 'auth' };
    if (res.status === 429) return { failure: 'rateLimit' };
    if (!res.ok) {
      console.error('sync-account-data: account info rejected', res.status);
      return { failure: res.status >= 500 ? 'server' : 'other' };
    }
    info = (await res.json()) as AnyRecord;
  } catch {
    console.error('sync-account-data: provider unreachable');
    return { failure: 'network' };
  }

  const equity = Number(info?.equity);
  const balance = Number(info?.balance);
  const connection = mapConnection(info?.connectionStatus ?? info?.state);

  // Open positions. A failure here is non-fatal: we still return the account info
  // with an empty list, so a positions hiccup never blanks the balance/equity.
  let positions: Position[] = [];
  try {
    const res = await fetch(
      `${METAAPI_BASE}/v3/accounts/${encodeURIComponent(providerAccountId)}/positions`,
      { headers },
    );
    if (res.ok) {
      positions = normalisePositions(await res.json());
    } else {
      console.error('sync-account-data: positions rejected', res.status);
    }
  } catch {
    console.error('sync-account-data: positions unreachable');
  }

  return {
    balance: Number.isFinite(balance) ? balance : Number.isFinite(equity) ? equity : 0,
    equity: Number.isFinite(equity) ? equity : 0,
    connection,
    positions,
  };
}


Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return json({}, 204);
  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed' }, 405);

  const userId = await callerId(req.headers.get('Authorization'));
  if (userId === null) return json({ ok: false, error: 'Unauthorized' }, 401);

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'Expected a JSON body.' }, 400);
  }

  const accountId = accountIdFrom(body);
  if (accountId === null) return json({ ok: false, error: 'account_id is required' }, 400);

  // deno-lint-ignore no-explicit-any
  let sb: any;
  try {
    sb = serviceClient();
  } catch (err) {
    console.error('sync-account-data: service client unavailable', String(err));
    return json({ ok: false, error: 'notConfigured' }, 503);
  }

  // Ownership is part of the WHERE clause. A row belonging to another user — or one
  // that does not exist — is simply not returned, so this is a 404 either way.
  const { data: rows, error } = await sb
    .from('broker_accounts')
    .select('id,metaapi_account_id')
    .eq('id', accountId)
    .eq('user_id', userId)
    .limit(1);

  if (error) {
    console.error('sync-account-data: account read failed');
    return json({ ok: false, error: 'server' }, 500);
  }

  const row = ((rows ?? []) as AnyRecord[])[0] ?? null;
  if (row === null) return json({ ok: false, error: 'Account not found' }, 404);

  const providerAccountId = row.metaapi_account_id;
  if (typeof providerAccountId !== 'string' || providerAccountId.length === 0) {
    // The account exists but was never linked to a broker. That is a "not linked"
    // state, not an error — the client renders it grey, never red.
    return json({
      ok: true,
      account_id: accountId,
      balance: 0,
      equity: 0,
      connection: 'offline',
      linked: false,
      positions: [],
      as_of: new Date().toISOString(),
    });
  }

  const result = await fetchAccount(providerAccountId);
  if ('failure' in result) {
    const status = result.failure === 'notConfigured' ? 503 : 502;
    return json({ ok: false, error: result.failure }, status);
  }

  return json({
    ok: true,
    account_id: accountId,
    balance: result.balance,
    equity: result.equity,
    connection: result.connection,
    linked: true,
    positions: result.positions,
    as_of: new Date().toISOString(),
  });
});

