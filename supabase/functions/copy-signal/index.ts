// copy-signal — computes risk-based lots and (optionally) places orders via MetaAPI.
//
//   POST /functions/v1/copy-signal
//     { signal_id, account_ids[], risk_pct, mode: 'paper' | 'live' }
//     -> { ok, mode, results: [{account_id, mode, lots, risk_pct, status, refusal?, order_id?}] }
//
// **PAPER MODE BY DEFAULT.** Live orders require ALL of: an exact 'live' in the request, a
// stored `copy_settings.live_consent` row, the kill switch OFF, per-account
// `broker_accounts.copy_enabled`, a linked `metaapi_account_id`, and lots under the cap.
// Every rule lives in `./shared.ts` (unit-tested in `copy_signal_test.ts`); this file adds only
// I/O. The lots that get written or ordered are recomputed here from server-side equity — the
// request's `risk_pct` is clamped, and the client's preview formula is fixture-tested to be
// identical — but no client-supplied size ever reaches a row or a broker.
//
// ── Authorization ─────────────────────────────────────────────────────────────────────────────
// User-facing (a trader taps Copy on a signal), so the gate is the `ai-review` shape, NOT the
// cron shape:
//   * `verify_jwt = true` (config.toml) rejects anonymous calls at the platform.
//   * The caller is resolved with GoTrue from their own bearer token; `user_id` is NEVER read
//     from the request body.
//   * Every read the service role performs is ownership-filtered on that verified id
//     (`.eq('user_id', userId)`), and an account id that is not the caller's simply does not
//     come back — it becomes an `accountMissing` refusal, identical to an account that does not
//     exist, so the endpoint cannot probe for other traders' account ids.
//
// ── Secrets ────────────────────────────────────────────────────────────────────────────────────
//   METAAPI_TOKEN   required for LIVE mode only — paper mode never touches MetaAPI. Without it,
//                   a live request fails with `notConfigured` (503); it is never downgraded to
//                   paper, because a trader who asked for live must not be shown a simulation
//                   believing it was an order.
//   SUPABASE_URL / SUPABASE_SERVICE_KEY / SUPABASE_ANON_KEY  required — platform-provided.
//
// Not covered by `flutter test`: needs a live Supabase project. The policy it applies is
// unit-tested in `copy_signal_test.ts`; the client half in `test/copy_*_test.dart`.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
  DEFAULT_SETTINGS,
  evaluateAccount,
  MODE_LIVE,
  validateBody,
} from './shared.ts';
import type { Mode, Refusal, SettingsCtx, SignalCtx } from './shared.ts';

// The same MetaAPI host `sync-trades` uses (docs/TRD.md §edge functions). The order command
// follows the v3 trading-commands shape: one market order per account, SL/TP carried from the
// signal, a fixed comment so copied positions are identifiable in the broker's journal.
const METAAPI_BASE = 'https://api.metavantage.com';
const COPY_COMMENT = 'TradeGuard copy-signal';

type AnyRecord = Record<string, unknown>;

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

// deno-lint-ignore no-explicit-any
function serviceClient(): any {
  const key = Deno.env.get('SUPABASE_SERVICE_KEY');
  const url = Deno.env.get('SUPABASE_URL');
  if (!key || !url) {
    throw new Error('SUPABASE_SERVICE_KEY / SUPABASE_URL is not set');
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** The caller's user id, resolved from their own bearer token (same contract as `ai-review`). */
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

/**
 * Places one live market order through MetaAPI.
 *
 * The token is read from the environment and used for exactly one header on exactly one request;
 * it is never logged and never returned. A non-2xx logs the STATUS ONLY — a MetaAPI error body
 * can echo the account identifier back. Returns the broker's order id, or null on failure.
 */
async function placeLiveOrder(input: {
  metaapiAccountId: string;
  pair: string;
  direction: string;
  lots: number;
  sl: number;
  tp: number;
}): Promise<string | null> {
  const token = Deno.env.get('METAAPI_TOKEN');
  if (!token) return null;

  const action = input.direction === 'sell' ? 'SELL' : 'BUY';
  let res: Response;
  try {
    res = await fetch(
      `${METAAPI_BASE}/v3/accounts/${encodeURIComponent(input.metaapiAccountId)}/trading-commands`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          command: 'executeTrade',
          tradeRequest: {
            symbol: input.pair,
            actionType: action,
            volume: input.lots,
            stopLoss: input.sl,
            takeProfit: input.tp,
            comment: COPY_COMMENT,
          },
        }),
      },
    );
  } catch {
    // Status unknown (transport failure). Never log the URL: it embeds the account id.
    console.error('copy-signal: provider unreachable');
    return null;
  }

  if (!res.ok) {
    console.error('copy-signal: provider rejected', res.status);
    return null;
  }

  try {
    const body = (await res.json()) as AnyRecord;
    const orderId = body.orderId ?? body.positionId ?? body.id;
    return typeof orderId === 'string' && orderId.length > 0 ? orderId : 'accepted';
  } catch {
    // A 2xx we cannot parse still means the command was accepted; the status stands in for the id.
    return 'accepted';
  }
}

/** One row of the per-account response. */
interface ResultRow {
  account_id: string;
  mode: Mode;
  lots: number;
  risk_pct: number;
  status: 'placed' | 'failed';
  refusal?: Refusal;
  order_id?: string;
  simulated?: boolean;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed' }, 405);

  const userId = await callerId(req.headers.get('Authorization'));
  if (userId === null) return json({ ok: false, error: 'Unauthorized' }, 401);

  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return json({ ok: false, error: 'Invalid body' }, 400);
  }

  const parsed = validateBody(raw);
  if (!parsed.ok) return json({ ok: false, error: parsed.error }, 400);
  const { signalId, accountIds, riskPct, mode } = parsed.body;

  // deno-lint-ignore no-explicit-any
  let sb: any;
  try {
    sb = serviceClient();
  } catch (err) {
    console.error('copy-signal: service client unavailable', String(err));
    return json({ ok: false, error: 'notConfigured' }, 503);
  }

  if (mode === MODE_LIVE && !Deno.env.get('METAAPI_TOKEN')) {
    // Config problem on the live path only. Paper still works — and a live request is never
    // downgraded to paper on our side.
    return json({ ok: false, error: 'notConfigured' }, 503);
  }

  // ── Signal (allowlist projection; `signals` holds no per-user data) ────────────────────────
  const { data: signalRows, error: signalError } = await sb
    .from('signals')
    .select('pair,direction,entry,sl,tp1,status')
    .eq('id', signalId)
    .limit(1);
  if (signalError) {
    console.error('copy-signal: signal read failed');
    return json({ ok: false, error: 'server' }, 500);
  }
  const signalRow = ((signalRows ?? []) as AnyRecord[])[0] ?? null;
  if (signalRow === null) return json({ ok: false, error: 'Signal not found' }, 404);

  const pair = String(signalRow.pair ?? '').trim().toUpperCase();
  const direction = String(signalRow.direction ?? '').trim().toLowerCase();
  const signal: SignalCtx = {
    status: String(signalRow.status ?? ''),
    entry: Number(signalRow.entry),
    sl: Number(signalRow.sl),
    tp1: Number(signalRow.tp1),
  };

  // ── Accounts: ownership is part of the WHERE clause ─────────────────────────────────────────
  const { data: accountRows, error: accountError } = await sb
    .from('broker_accounts')
    .select('id,metaapi_account_id,copy_enabled,initial_balance')
    .eq('user_id', userId)
    .in('id', accountIds);
  if (accountError) {
    console.error('copy-signal: account read failed');
    return json({ ok: false, error: 'server' }, 500);
  }
  const owned = new Map<string, AnyRecord>();
  for (const row of (accountRows ?? []) as AnyRecord[]) {
    if (typeof row.id === 'string') owned.set(row.id, row);
  }

  // ── Equity: latest snapshot per account, falling back to initial_balance ───────────────────
  // (Same rule as the client's account merge: a freshly connected account starts at its initial
  // balance rather than an invented live reading. Equity is NEVER taken from the request.)
  const { data: snapRows } = await sb
    .from('equity_snapshots')
    .select('account_id,equity')
    .in('account_id', [...owned.keys()])
    .order('created_at', { ascending: false })
    .limit(500);
  const equity = new Map<string, number>();
  for (const row of (snapRows ?? []) as AnyRecord[]) {
    const id = row.account_id as string;
    if (!equity.has(id)) equity.set(id, Number(row.equity) || 0);
  }

  // ── Settings + open-follow count ────────────────────────────────────────────────────────────
  const { data: settingRows } = await sb
    .from('copy_settings')
    .select('live_consent,kill_switch,max_lots,max_concurrent_follows')
    .eq('user_id', userId)
    .limit(1);
  const s = ((settingRows ?? []) as AnyRecord[])[0] ?? null;
  const settings: SettingsCtx = {
    liveConsent: s?.live_consent === true,
    killSwitch: s?.kill_switch === true,
    maxLots: Number(s?.max_lots) > 0 ? Number(s.max_lots) : DEFAULT_SETTINGS.maxLots,
    maxConcurrentFollows:
      Number.isFinite(Number(s?.max_concurrent_follows)) && Number(s?.max_concurrent_follows) > 0
        ? Number(s.max_concurrent_follows)
        : DEFAULT_SETTINGS.maxConcurrentFollows,
  };

  const { count: openCount } = await sb
    .from('signal_follows')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .in('copy_status', ['pending', 'placed']);
  let openFollows = Number(openCount) || 0;

  // ── Evaluate every requested account, in request order ──────────────────────────────────────
  const results: ResultRow[] = [];
  const followRows: AnyRecord[] = [];

  for (const accountId of accountIds) {
    const row = owned.get(accountId);
    const accountEquity =
      equity.get(accountId) ?? (row ? Number(row.initial_balance) || 0 : 0);

    const verdict = evaluateAccount({
      pair,
      signal,
      account: {
        id: accountId,
        equity: accountEquity,
        copyEnabled: row?.copy_enabled === true,
        metaapiAccountId:
          typeof row?.metaapi_account_id === 'string' ? row.metaapi_account_id : null,
      },
      settings,
      requestedMode: mode,
      riskPct,
      openFollows,
      accountExists: row !== undefined,
    });

    if (verdict.refusal !== null) {
      results.push({
        account_id: accountId,
        mode: verdict.mode,
        lots: 0,
        risk_pct: riskPct,
        status: 'failed',
        refusal: verdict.refusal,
      });
      continue;
    }

    if (verdict.mode === MODE_LIVE) {
      const orderId = await placeLiveOrder({
        metaapiAccountId: row!.metaapi_account_id as string,
        pair,
        direction,
        lots: verdict.lots,
        sl: signal.sl,
        tp: signal.tp1,
      });
      if (orderId === null) {
        results.push({
          account_id: accountId,
          mode: MODE_LIVE,
          lots: verdict.lots,
          risk_pct: riskPct,
          status: 'failed',
        });
        continue;
      }
      followRows.push({
        user_id: userId,
        signal_id: signalId,
        account_id: accountId,
        lots: verdict.lots,
        risk_pct: riskPct,
        mode: MODE_LIVE,
        copy_status: 'placed',
        order_id: orderId,
      });
      results.push({
        account_id: accountId,
        mode: MODE_LIVE,
        lots: verdict.lots,
        risk_pct: riskPct,
        status: 'placed',
        order_id: orderId,
      });
      openFollows++;
    } else {
      // Paper: simulated fill, logged as a follow so the ledger and the concurrent cap see it.
      followRows.push({
        user_id: userId,
        signal_id: signalId,
        account_id: accountId,
        lots: verdict.lots,
        risk_pct: riskPct,
        mode: 'paper',
        copy_status: 'placed',
      });
      results.push({
        account_id: accountId,
        mode: 'paper',
        lots: verdict.lots,
        risk_pct: riskPct,
        status: 'placed',
        simulated: true,
      });
      openFollows++;
    }
  }

  // ── Persist the placed follows (service role; user_id from the verified JWT, never the body) ─
  if (followRows.length > 0) {
    const { error: followError } = await sb.from('signal_follows').insert(followRows);
    if (followError) {
      // The broker order (if any) is already out; report the write failure honestly rather than
      // pretending the ledger recorded it. Logged with the code only.
      console.error('copy-signal: follow write failed', followError.code);
      return json({ ok: false, error: 'server' }, 500);
    }
  }

  return json({ ok: true, mode, results });
});

