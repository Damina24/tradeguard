// sync-trades — cron 5/min (migration `0005_sync_trades.sql`).
//
// Pulls closed deals for every active, provider-linked broker account and upserts them into
// `trades`, advancing a per-account cursor (`trade_sync_cursors`) so each run is incremental
// rather than a full re-read.
//
//   POST /functions/v1/sync-trades  {}             -> all eligible accounts
//   POST /functions/v1/sync-trades  {account_id}   -> one account (manual refresh)
//
// All policy lives in `./shared.ts` (windowing, backoff, eligibility, field mapping, the
// service-role gate) so it is unit-tested without a runtime. This file adds only I/O.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
  authorized,
  classifyStatus,
  eligibleAccounts,
  nextWatermark,
  toTradeRow,
  windowStartMs,
} from './shared.ts';
import type { SyncAccount, SyncCursorRow } from './shared.ts';

const METAAPI_BASE = 'https://api.metavantage.com';

type AnyRecord = Record<string, unknown>;

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function supabase() {
  const key = Deno.env.get('SUPABASE_SERVICE_KEY');
  const url = Deno.env.get('SUPABASE_URL');
  if (!key || !url) throw new Error('SUPABASE_SERVICE_KEY / SUPABASE_URL is not set');
  return createClient(url, key);
}

/**
 * One page of deals, or a failure classification.
 *
 * The token is read from the environment and used for exactly one header on exactly one request;
 * it is never logged and never returned.
 */
async function fetchDeals(
  providerAccountId: string,
  fromMs: number,
  limit: number,
): Promise<{ deals: AnyRecord[] } | { failure: string }> {
  const token = Deno.env.get('METAAPI_TOKEN');
  if (!token) return { failure: 'notConfigured' };

  const url =
    `${METAAPI_BASE}/v3/accounts/${encodeURIComponent(providerAccountId)}/deals` +
    `?limit=${limit}&from=${new Date(fromMs).toISOString()}`;

  let res: Response;
  try {
    res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  } catch {
    // Status unknown (transport failure). Never log the URL: it embeds the account id.
    console.error('sync-trades: provider unreachable');
    return { failure: 'network' };
  }

  if (!res.ok) {
    // Status only: a MetaAPI error body can echo the account identifier back.
    console.error('sync-trades: provider rejected', res.status);
    return { failure: classifyStatus(res.status) };
  }

  let body: unknown;
  try {
    body = await res.json();
  } catch {
    return { failure: 'malformed' };
  }

  const raw = Array.isArray(body)
    ? body
    : ((body as AnyRecord)?.deals ?? (body as AnyRecord)?.trades);
  if (!Array.isArray(raw)) return { failure: 'malformed' };

  const deals: AnyRecord[] = [];
  for (const entry of raw) {
    // A non-object entry is dropped rather than failing the page: one odd record must not cost
    // the trader the rest of the window.
    if (entry && typeof entry === 'object' && !Array.isArray(entry)) {
      deals.push(entry as AnyRecord);
    }
  }
  return { deals };
}
/**
 * Syncs one account end to end and advances its cursor.
 *
 * The cursor only moves on success, so a failed run re-reads the same window on the next
 * attempt instead of skipping trades that arrived during the outage.
 */
// deno-lint-ignore no-explicit-any
async function syncAccount(sb: any, account: SyncAccount, nowMs: number): Promise<AnyRecord> {
  const stats = { fetched: 0, imported: 0, skipped: 0 };

  const { data: cursorRows } = await sb
    .from('trade_sync_cursors')
    .select('account_id,last_synced_at,last_external_id,last_run_at,consecutive_failures')
    .eq('account_id', account.id)
    .limit(1);
  const cursor: SyncCursorRow | undefined = cursorRows && cursorRows[0];

  const fromMs = windowStartMs(cursor?.last_synced_at ?? null, nowMs);
  const result = await fetchDeals(account.metaapi_account_id as string, fromMs, 500);
  const lastRunIso = new Date(nowMs).toISOString();

  /** Records the failure WITHOUT moving the watermark. */
  const fail = async (reason: string) => {
    await sb.from('trade_sync_cursors').upsert(
      {
        account_id: account.id,
        user_id: account.user_id,
        last_synced_at: cursor?.last_synced_at ?? null,
        last_external_id: cursor?.last_external_id ?? null,
        last_run_at: lastRunIso,
        consecutive_failures: (cursor?.consecutive_failures ?? 0) + 1,
      },
      { onConflict: 'account_id' },
    );
    return { account_id: account.id, ...stats, failure: reason };
  };

  if ('failure' in result) return await fail(result.failure);

  const rows: AnyRecord[] = [];
  for (const deal of result.deals) {
    stats.fetched += 1;
    const row = toTradeRow(deal, account.id, account.user_id);
    if (row) rows.push(row);
    else stats.skipped += 1;
  }

  if (rows.length > 0) {
    // The unique key is (account_id, external_id) — migration 0005 corrected it from
    // (user_id, external_id), which collided across a trader's two broker accounts. Upserting on
    // that key is what makes a re-run update the row instead of inserting a second one.
    const { error } = await sb
      .from('trades')
      .upsert(rows, { onConflict: 'account_id,external_id' });
    if (error) {
      console.error('sync-trades: upsert failed', account.id, error.message);
      return await fail('persistence');
    }
    stats.imported = rows.length;
  }

  const watermark = nextWatermark(rows, nowMs);
  const previous = cursor?.last_synced_at ?? null;
  await sb.from('trade_sync_cursors').upsert(
    {
      account_id: account.id,
      user_id: account.user_id,
      // Only ever moves FORWARD: a deal whose timestamp predates the watermark (a late
      // correction) must not rewind progress and make the account re-read forever.
      last_synced_at:
        previous && Date.parse(previous) > Date.parse(watermark) ? previous : watermark,
      last_external_id: rows.length > 0 ? rows[rows.length - 1].external_id : null,
      last_run_at: lastRunIso,
      consecutive_failures: 0,
    },
    { onConflict: 'account_id' },
  );

  return { account_id: account.id, ...stats };
}
Deno.serve(async (req: Request): Promise<Response> => {
  const nowMs = Date.now();

  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed' }, 405);

  // Same gate as guard-check: verify_jwt stops anonymous callers, this stops a normal user JWT
  // from making us spend MetaAPI allowance on demand.
  if (!authorized(req.headers.get('Authorization'), Deno.env.get('SUPABASE_SERVICE_KEY'))) {
    return json({ ok: false, error: 'Unauthorized' }, 401);
  }

  let requestedAccountId: string | null = null;
  try {
    const body = (await req.json()) as AnyRecord;
    const id = body.account_id;
    // Used only to SELECT candidates below, never to choose a write target.
    requestedAccountId = typeof id === 'string' && id.length > 0 ? id : null;
  } catch {
    // An empty body is valid: it means "sync everything eligible".
    requestedAccountId = null;
  }

  const summary = { checked: 0, synced: 0, imported: 0, skipped: 0, failed: 0 };

  try {
    // deno-lint-ignore no-explicit-any
    const sb: any = supabase();

    const { data: accountRows, error } = await sb
      .from('broker_accounts')
      .select('id,user_id,nickname,metaapi_account_id,is_active')
      .eq('is_active', true);
    if (error) throw error;

    let accounts = (accountRows ?? []) as SyncAccount[];
    if (requestedAccountId) {
      // Defence in depth: the id must exist among our own active accounts. Combined with the
      // service-role gate this closes the IDOR path on the manual-refresh body.
      accounts = accounts.filter((a) => a.id === requestedAccountId);
      if (accounts.length === 0) {
        return json({ ok: false, error: 'Account not found' }, 404);
      }
    }

    const { data: cursorRows } = await sb
      .from('trade_sync_cursors')
      .select('account_id,last_synced_at,last_external_id,last_run_at,consecutive_failures');
    const cursors = new Map<string, SyncCursorRow>();
    for (const row of (cursorRows ?? []) as SyncCursorRow[]) {
      cursors.set(row.account_id, row);
    }

    const eligible = eligibleAccounts(accounts, cursors, nowMs);
    summary.checked = eligible.length;

    for (const account of eligible) {
      try {
        const result = await syncAccount(sb, account, nowMs);
        if ('failure' in result) {
          summary.failed += 1;
          console.error('sync-trades: account failed', account.id, result.failure);
        } else {
          summary.synced += 1;
          summary.imported += result.imported as number;
          summary.skipped += result.skipped as number;
        }
      } catch (err) {
        // One account must never abort the run: the rest are independent.
        summary.failed += 1;
        console.error('sync-trades: account threw', account.id, String(err));
      }
    }
  } catch (err) {
    return json({ ok: false, error: String(err) }, 500);
  }

  return json({ ok: true, at: new Date(nowMs).toISOString(), ...summary });
});