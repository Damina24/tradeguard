// guard-check — cron 1/min.
//
// Snapshots equity for every active, guard-enabled broker account; maintains `peak_equity` so
// trailing drawdown is computable (migration 0003); and raises ONE push the first time an account
// crosses 70% / 90% / 100% of its daily loss limit.
//
// Secrets (`supabase secrets set ...`):
//   SERVICE_ROLE_KEY       required
//   METAAPI_TOKEN             optional — without it we re-use the last known equity instead of failing
//   FIREBASE_SERVICE_ACCOUNT  optional — without it we compute + store but do not push
//
// Scheduling: migration `0004_guard_check_cron.sql` runs this every minute through pg_cron + pg_net
// and presents the service-role key. See `docs/BACKEND_DEPLOY.md`.
//
// Crossing detection is `prevUsed < T <= nowUsed` against the previous snapshot, which is exactly
// the rule `GuardAlertEvaluator` applies in the Flutter app, so server and client can never
// disagree about when an alert fires. Every level is edge-triggered, so an account that stays in
// breach produces one push, not one per minute.
//
// Not covered by `flutter test`: this needs a live Supabase project plus MetaAPI and Firebase
// credentials. The pure helpers below (dailyLossPct / drawdownDistance / computeGuard / alertFor)
// mirror `TradingMath` + `GuardAlertEvaluator` on the client and are safe to unit test on their own.

export type GuardState = 'ok' | 'warn' | 'critical' | 'breach';
export type AlertLevel = 'warn' | 'critical' | 'breach';

export interface BrokerAccount {
  id: string;
  nickname: string;
  metaapi_account_id: string | null;
  initial_balance: number;
  daily_loss_limit: number;
  max_drawdown: number;
  drawdown_type: 'static' | 'trailing';
  equity_guard_enabled: boolean;
  is_active: boolean;
}

export interface Reading {
  equity: number;
  balance: number;
  dailyPnl: number;
  peakEquity: number;
}

export interface Verdict {
  state: GuardState;
  dailyUsedPct: number;
  drawdownDistance: number;
}

/** Mirrors `TradingMath.dailyLossPct`: |loss| / limit * 100, rounded to 1dp. */
export function dailyLossPct(dailyPnl: number, dailyLossLimit: number): number {
  if (dailyLossLimit <= 0) return 0;
  const loss = dailyPnl < 0 ? -dailyPnl : 0;
  return Math.round(((loss / dailyLossLimit) * 100) * 10) / 10;
}

/** Mirrors `TradingMath.drawdownDistance`: currency left before the floor, never negative. */
export function drawdownDistance(
  account: BrokerAccount,
  equity: number,
  peakEquity: number,
): number {
  const reference =
    account.drawdown_type === 'trailing' ? peakEquity : account.initial_balance;
  return Math.max(0, equity - (reference - account.max_drawdown));
}

export function computeGuard(account: BrokerAccount, reading: Reading): Verdict {
  const used = dailyLossPct(reading.dailyPnl, account.daily_loss_limit);
  const dd = drawdownDistance(account, reading.equity, reading.peakEquity);

  let state: GuardState = 'ok';
  if (dd <= 0 || used >= 100) state = 'breach';
  else if (used >= 90) state = 'critical';
  else if (used >= 70) state = 'warn';

  return { state, dailyUsedPct: used, drawdownDistance: dd };
}

/** The level to alert on for this transition, or null. Mirrors `GuardAlertEvaluator.evaluate`. */
export function alertFor(
  previous: Verdict | null,
  next: Verdict,
): AlertLevel | null {
  const before = previous?.dailyUsedPct ?? 0;
  const beforeBreached = previous?.state === 'breach' || before >= 100;

  if (next.state === 'breach' && !beforeBreached) return 'breach';
  if (next.dailyUsedPct >= 90 && before < 90) return 'critical';
  if (next.dailyUsedPct >= 70 && before < 70) return 'warn';
  return null;
}

/** Peak equity only ever ratchets upward. */
export function nextPeak(previousPeak: number, equity: number): number {
  return Math.max(previousPeak || 0, equity);
}

/** Copy is factual — it reports a number and never advises on a trade. */
export function alertTitle(level: AlertLevel): string {
  switch (level) {
    case 'warn':
      return 'Loss limit 70% used';
    case 'critical':
      return 'Loss limit 90% used';
    default:
      return 'Guard breach';
  }
}

export function alertBody(level: AlertLevel, nickname: string): string {
  switch (level) {
    case 'warn':
      return `${nickname} has used 70% of today's loss limit.`;
    case 'critical':
      return `${nickname} has used 90% of today's loss limit.`;
    default:
      return `${nickname} reached its limit. Open TradeGuard to review.`;
  }
}

/** FCM topics allow only [a-zA-Z0-9-_.~%]; must match `FcmPushService` on the client. */
export function topicFor(accountId: string): string {
  return `guard_${accountId.replace(/[^a-zA-Z0-9_-]/g, '-')}`;
}

export function utcDayStart(now: Date): Date {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const METAAPI_BASE = 'https://api.metavantage.com';

type AnyRecord = Record<string, unknown>;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function supabase() {
  const key = Deno.env.get('SERVICE_ROLE_KEY');
  const url = Deno.env.get('SUPABASE_URL');
  if (!key || !url) throw new Error('SERVICE_ROLE_KEY / SUPABASE_URL is not set');
  return createClient(url, key);
}

/** Equity + balance from MetaAPI, or null when unreachable/absent. */
async function fetchBrokerEquity(
  accountId: string,
): Promise<{ equity: number; balance: number } | null> {
  const token = Deno.env.get('METAAPI_TOKEN');
  if (!token) return null;
  try {
    const res = await fetch(`${METAAPI_BASE}/v3/accounts/${accountId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) return null;
    const body = (await res.json()) as AnyRecord;
    const equity = Number(body.equity);
    if (!Number.isFinite(equity)) return null;
    const balance = Number(body.balance);
    return { equity, balance: Number.isFinite(balance) ? balance : equity };
  } catch {
    return null;
  }
}

interface SnapshotRow {
  equity: number;
  balance: number;
  daily_pnl: number;
  peak_equity: number;
  created_at: string;
}

/** Newest snapshot for an account, or null on first run. */
// deno-lint-ignore no-explicit-any
async function lastSnapshot(sb: any, accountId: string): Promise<SnapshotRow | null> {
  const { data, error } = await sb
    .from('equity_snapshots')
    .select('equity,balance,daily_pnl,peak_equity,created_at')
    .eq('account_id', accountId)
    .order('created_at', { ascending: false })
    .limit(1);
  if (error) throw error;
  return (data && data[0]) || null;
}

/** Equity at the start of the current UTC day; daily P&L is measured against it. */
// deno-lint-ignore no-explicit-any
async function dayStartEquity(sb: any, accountId: string, now: Date): Promise<number | null> {
  const { data, error } = await sb
    .from('equity_snapshots')
    .select('equity,created_at')
    .eq('account_id', accountId)
    .lt('created_at', utcDayStart(now).toISOString())
    .order('created_at', { ascending: false })
    .limit(1);
  if (error) throw error;
  const row = data && data[0];
  return row ? Number(row.equity) : null;
}

/** How much minute-level history to keep. ~43k rows per account at 30 days. */
export const SNAPSHOT_RETENTION_DAYS = 30;

/**
 * Daily at 03:00 UTC.
 *
 * Pruning on a fixed minute means the delete runs once a day instead of on all 1440 invocations.
 * If the scheduler is down for that minute the window simply rolls forward a day — harmless.
 */
export function shouldPrune(now: Date): boolean {
  return now.getUTCHours() === 3 && now.getUTCMinutes() === 0;
}

/**
 * Whether the caller may spend MetaAPI allowance on demand.
 *
 * `verify_jwt = false` on this function means the platform checks nothing, so the function checks
 * for itself: the cron job presents the service-role key. Without this, anyone who guessed the URL
 * could force us to re-read every connected account's equity once a minute.
 *
 * With no key configured (`supabase functions serve` locally) the host is trusted, because there is
 * nothing to compare against.
 */
export function authorized(
  header: string | null,
  serviceKey: string | undefined,
): boolean {
  if (!serviceKey) return true;
  if (!header || !header.startsWith('Bearer ')) return false;
  return header.slice('Bearer '.length).trim() === serviceKey;
}

/** Deletes snapshots past the retention window. Runs with the service key, so RLS is bypassed. */
async function pruneSnapshots(sb: any, now: Date): Promise<number> {
  const cutoff = new Date(
    now.getTime() - SNAPSHOT_RETENTION_DAYS * 86_400_000,
  ).toISOString();
  const { count, error } = await sb
    .from('equity_snapshots')
    .delete({ count: 'exact' })
    .lt('created_at', cutoff);
  if (error) throw error;
  return count ?? 0;
}

type Notifier = (topic: string, title: string, body: string) => Promise<void>;

/** Firebase Admin notifier, or null when `FIREBASE_SERVICE_ACCOUNT` is absent. */
async function pushNotifier(): Promise<Notifier | null> {
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
  if (!raw) return null;
  try {
    const { cert, initializeApp } = await import('https://esm.sh/firebase-admin@11/app');
    const { getMessaging } = await import('https://esm.sh/firebase-admin@11/messaging');
    const client = getMessaging(initializeApp(cert(JSON.parse(raw))));
    return async (topic, title, body) => {
      await client.send({
        topic,
        notification: { title, body },
        android: { priority: 'high', notification: { channelId: 'guard_alerts' } },
      });
    };
  } catch (err) {
    console.error('guard-check: push unavailable', err);
    return null;
  }
}

Deno.serve(async (req: Request) => {
  const now = new Date();
  const summary = { checked: 0, snapshots: 0, alerts: 0, skipped: 0, pruned: 0 };

  if (!authorized(req.headers.get('Authorization'), Deno.env.get('SERVICE_ROLE_KEY'))) {
    return json({ ok: false, error: 'Unauthorized' }, 401);
  }

  try {
    // deno-lint-ignore no-explicit-any
    const sb: any = supabase();
    const notify = await pushNotifier();

    const { data: accounts, error } = await sb
      .from('broker_accounts')
      .select(
        'id,nickname,metaapi_account_id,initial_balance,daily_loss_limit,max_drawdown,' +
          'drawdown_type,equity_guard_enabled,is_active',
      )
      .eq('is_active', true)
      .eq('equity_guard_enabled', true);

    if (error) throw error;
    summary.checked = (accounts || []).length;

    // Minute-level history is unbounded without this (525k rows/account/year), so the retention
    // sweep is part of the same job that produces the rows.
    if (shouldPrune(now)) summary.pruned = await pruneSnapshots(sb, now);

    for (const account of (accounts || []) as BrokerAccount[]) {
      try {
        const prevRow = await lastSnapshot(sb, account.id);
        const live = account.metaapi_account_id
          ? await fetchBrokerEquity(account.metaapi_account_id)
          : null;

        // Falling back to the last known equity keeps the guard honest (it degrades to STALE via
        // snapshot age) instead of inventing numbers or failing the whole run.
        const equity = live?.equity ?? (prevRow ? Number(prevRow.equity) : null);
        if (equity === null || !Number.isFinite(equity)) {
          summary.skipped += 1;
          continue;
        }

        const balance = live?.balance ?? (prevRow ? Number(prevRow.balance) : equity);
        const peakEquity = nextPeak(prevRow ? Number(prevRow.peak_equity) : 0, equity);
        const base = await dayStartEquity(sb, account.id, now);
        const dailyPnl = base === null ? 0 : equity - base;

        const next = computeGuard(account, { equity, balance, dailyPnl, peakEquity });
        const previous = prevRow
          ? computeGuard(account, {
              equity: Number(prevRow.equity),
              balance: Number(prevRow.balance),
              dailyPnl: Number(prevRow.daily_pnl),
              peakEquity: Number(prevRow.peak_equity),
            })
          : null;

        const { error: insertError } = await sb.from('equity_snapshots').insert({
          account_id: account.id,
          equity,
          balance,
          drawdown_used: Math.max(0, account.max_drawdown - next.drawdownDistance),
          daily_pnl: dailyPnl,
          peak_equity: peakEquity,
        });
        if (insertError) throw insertError;
        summary.snapshots += 1;

        const level = alertFor(previous, next);
        if (level) {
          summary.alerts += 1;
          if (notify) {
            await notify(
              topicFor(account.id),
              alertTitle(level),
              alertBody(level, account.nickname),
            );
          }
        }
      } catch (err) {
        summary.skipped += 1;
        console.error('guard-check: account failed', account.id, err);
      }
    }
  } catch (err) {
    return json({ ok: false, error: String(err) }, 500);
  }

  return json({ ok: true, at: now.toISOString(), ...summary });
});

