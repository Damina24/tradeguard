// Pure-logic tests for `sync-trades`.
//
// These need neither Deno nor credentials: they exercise the exported helpers only, so the
// security rules (the service-role gate), the incremental window and the field mapping are all
// verified in CI. The HTTP handler needs a live Supabase project plus a MetaAPI token and is
// verified by the deploy steps in `docs/BACKEND_DEPLOY.md`.
//
// The Dart suite in `test/trade_sync_*_test.dart` tests the same rules on the client side; the
// two are intentionally parallel, and `toTradeRow` here mirrors `TradeSyncMapper`.
//
// Run with:  node supabase/functions/sync-trades/sync-trades_test.ts
// (Node 22+ strips the types natively. `deno test` works too.)

import {
  classifyStatus,
  dealDirection,
  dealExternalId,
  eligibleAccounts,
  authorized,
  INITIAL_SYNC_WINDOW_DAYS,
  isDue,
  isoDate,
  MAX_WINDOW_DAYS,
  nextWatermark,
  num,
  toTradeRow,
  windowStartMs,
} from './shared.ts';
import type { SyncAccount } from './shared.ts';

let passed = 0;
const failures: string[] = [];

function test(name: string, fn: () => void): void {
  try {
    fn();
    passed++;
  } catch (err) {
    failures.push(`${name}: ${err instanceof Error ? err.message : String(err)}`);
  }
}

function eq(actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`expected ${e}, got ${a}`);
}

function ok(value: boolean, note = ''): void {
  if (!value) throw new Error(`expected truthy ${note}`);
}

const NOW = Date.parse('2026-04-20T12:00:00.000Z');
const DAY = 86_400_000;

// ---------------------------------------------------------------------------------------------
// Authorization — the security gate
// ---------------------------------------------------------------------------------------------

test('rejects a missing Authorization header', () => {
  ok(authorized(null, 'service-key') === false);
});

test('rejects a wrong bearer token', () => {
  ok(authorized('Bearer nope', 'service-key') === false);
});

test('rejects a non-bearer scheme', () => {
  ok(authorized('Basic service-key', 'service-key') === false);
});

test('rejects a bearer with trailing junk', () => {
  ok(authorized('Bearer service-key extra', 'service-key') === false);
});

test('accepts the exact service-role bearer', () => {
  ok(authorized('Bearer service-key', 'service-key') === true);
});

test('trusts the host when no key is configured (local serve only)', () => {
  ok(authorized(null, undefined) === true);
});

// ---------------------------------------------------------------------------------------------
// Windowing
// ---------------------------------------------------------------------------------------------

test('a first run is bounded to the initial window', () => {
  eq(windowStartMs(null, NOW), NOW - INITIAL_SYNC_WINDOW_DAYS * DAY);
});

test('an unparseable watermark falls back to the initial window', () => {
  eq(windowStartMs('not-a-date', NOW), NOW - INITIAL_SYNC_WINDOW_DAYS * DAY);
});

test('a returning account re-reads the overlap', () => {
  const last = new Date(NOW - 2 * DAY).toISOString();
  eq(windowStartMs(last, NOW), NOW - 2 * DAY - 6 * 3_600_000);
});

test('the window is clamped to the maximum', () => {
  const ancient = new Date(NOW - 500 * DAY).toISOString();
  eq(windowStartMs(ancient, NOW), NOW - MAX_WINDOW_DAYS * DAY);
});

// ---------------------------------------------------------------------------------------------
// Backoff
// ---------------------------------------------------------------------------------------------

test('a never-run account is always due', () => {
  ok(isDue(null, 0, NOW) === true);
});

test('a healthy account is always due', () => {
  ok(isDue(new Date(NOW - 1000).toISOString(), 0, NOW) === true);
});

test('a once-failed account waits one minute', () => {
  ok(isDue(new Date(NOW - 30_000).toISOString(), 1, NOW) === false);
  ok(isDue(new Date(NOW - 90_000).toISOString(), 1, NOW) === true);
});

test('backoff grows exponentially and caps at an hour', () => {
  // 2 failures -> wait 2 minutes, so a run 90s old is not yet due.
  ok(isDue(new Date(NOW - 90_000).toISOString(), 2, NOW) === false);
  // 4 failures -> wait 8 minutes.
  ok(isDue(new Date(NOW - 5 * 60_000).toISOString(), 4, NOW) === false);
  ok(isDue(new Date(NOW - 9 * 60_000).toISOString(), 4, NOW) === true);
  // Even 10 failures cap at 60 minutes, so 61 minutes is always enough.
  ok(isDue(new Date(NOW - 61 * 60_000).toISOString(), 10, NOW) === true);
  // ...and the cap really is an hour: 59 minutes is still not enough at 10 failures.
  ok(isDue(new Date(NOW - 59 * 60_000).toISOString(), 10, NOW) === false);
});

test('a malformed last_run_at does not wedge the account', () => {
  ok(isDue('garbage', 5, NOW) === true);
});
// ---------------------------------------------------------------------------------------------
// Eligibility / account isolation
// ---------------------------------------------------------------------------------------------

const account = (over: Partial<SyncAccount> = {}): SyncAccount => ({
  id: 'acc-1',
  user_id: 'user-1',
  nickname: 'FTMO EVAL',
  metaapi_account_id: 'meta-1',
  is_active: true,
  ...over,
});

test('an active, provider-linked account is eligible', () => {
  eq(eligibleAccounts([account()], new Map(), NOW).length, 1);
});

test('an inactive account is skipped', () => {
  eq(eligibleAccounts([account({ is_active: false })], new Map(), NOW).length, 0);
});

test('an account with no provider link is skipped', () => {
  eq(
    eligibleAccounts([account({ metaapi_account_id: null })], new Map(), NOW)
      .length,
    0,
  );
});

test('an account in backoff is skipped', () => {
  const cursors = new Map([
    [
      'acc-1',
      {
        account_id: 'acc-1',
        last_synced_at: null,
        last_external_id: null,
        last_run_at: new Date(NOW - 1000).toISOString(),
        consecutive_failures: 3,
      },
    ],
  ]);
  eq(eligibleAccounts([account()], cursors, NOW).length, 0);
});

test('one backing-off account does not block its neighbours', () => {
  const cursors = new Map([
    [
      'acc-1',
      {
        account_id: 'acc-1',
        last_synced_at: null,
        last_external_id: null,
        last_run_at: new Date(NOW - 1000).toISOString(),
        consecutive_failures: 4,
      },
    ],
  ]);
  const both = [account(), account({ id: 'acc-2', metaapi_account_id: 'meta-2' })];
  const eligible = eligibleAccounts(both, cursors, NOW);
  eq(eligible.length, 1);
  eq(eligible[0].id, 'acc-2');
});

// ---------------------------------------------------------------------------------------------
// Field extraction
// ---------------------------------------------------------------------------------------------

test('reads the deal id from several provider spellings', () => {
  eq(dealExternalId({ id: 12 }), '12');
  eq(dealExternalId({ ticket: 'A1' }), 'A1');
  eq(dealExternalId({ dealId: 'D-9' }), 'D-9');
  eq(dealExternalId({ positionId: 'P3' }), 'P3');
});

test('a missing or blank deal id is refused', () => {
  eq(dealExternalId({}), null);
  eq(dealExternalId({ id: '   ' }), null);
  eq(dealExternalId({ id: null }), null);
});

test('reads direction as a word or a number', () => {
  eq(dealDirection({ type: 'buy' }), 'long');
  eq(dealDirection({ type: 'SELL' }), 'short');
  eq(dealDirection({ side: 1 }), 'long');
  eq(dealDirection({ side: -1 }), 'short');
});

test('an unreadable direction is refused', () => {
  eq(dealDirection({ type: 'sideways' }), null);
  eq(dealDirection({}), null);
  eq(dealDirection({ side: 0 }), null);
});

test('num rejects junk and accepts numeric strings', () => {
  eq(num('12.5'), 12.5);
  eq(num(3), 3);
  eq(num('abc'), null);
  eq(num(NaN), null);
  eq(num(''), null);
  eq(num(null), null);
});

test('isoDate drops unparseable input rather than guessing', () => {
  eq(isoDate('2026-04-15T08:30:00Z'), '2026-04-15T08:30:00.000Z');
  eq(isoDate('nope'), null);
  eq(isoDate(12345), null);
  eq(isoDate(''), null);
});
// ---------------------------------------------------------------------------------------------
// Row mapping
// ---------------------------------------------------------------------------------------------

const goodDeal = {
  id: 900001,
  openTime: '2026-04-15T08:30:00Z',
  closeTime: '2026-04-15T12:00:00Z',
  type: 'buy',
  volume: 0.5,
  symbol: 'XAUUSD',
  openPrice: 2345.1,
  closePrice: 2351.4,
  sl: 2340,
  tp: 2351.4,
  profit: 312,
  commission: -3.5,
  swap: -0.7,
};

test('maps a good deal onto a trades row', () => {
  const row = toTradeRow(goodDeal, 'acc-1', 'user-1')!;
  eq(row.account_id, 'acc-1');
  eq(row.external_id, '900001');
  eq(row.symbol, 'XAUUSD');
  eq(row.direction, 'long');
  eq(row.lots, 0.5);
  eq(row.entry, 2345.1);
  eq(row.exit, 2351.4);
});

test('the row carries user_id, which the table declares NOT NULL', () => {
  // Regression guard: omitting this made every sync insert fail at runtime.
  const row = toTradeRow(goodDeal, 'acc-1', 'user-1')!;
  eq(row.user_id, 'user-1');
});

test('no provider credential is ever placed on a row', () => {
  const row = toTradeRow(
    { ...goodDeal, token: 'SECRET', apiKey: 'SECRET', login: 'SECRET' },
    'acc-1',
    'user-1',
  )!;
  eq(Object.values(row).includes('SECRET'), false);
});

test('pnl is net of commission and swap', () => {
  const row = toTradeRow(goodDeal, 'acc-1', 'user-1')!;
  eq(row.pnl, 312 - 3.5 - 0.7);
});

test('a missing optional price is null, not zero', () => {
  const row = toTradeRow({ ...goodDeal, sl: undefined, tp: undefined }, 'acc-1', 'user-1')!;
  eq(row.sl, null);
  eq(row.tp, null);
});

test('the symbol is upper-cased', () => {
  eq(toTradeRow({ ...goodDeal, symbol: 'eurusd' }, 'acc-1', 'user-1')!.symbol, 'EURUSD');
});

test('a deal with no id is refused', () => {
  const { id: _id, ...noId } = goodDeal;
  eq(toTradeRow(noId, 'acc-1', 'user-1'), null);
});

test('a deal with no symbol is refused', () => {
  const { symbol: _symbol, ...noSymbol } = goodDeal;
  eq(toTradeRow(noSymbol, 'acc-1', 'user-1'), null);
});

test('a deal with an impossible size is refused', () => {
  eq(toTradeRow({ ...goodDeal, volume: 0 }, 'acc-1', 'user-1'), null);
  eq(toTradeRow({ ...goodDeal, volume: -1 }, 'acc-1', 'user-1'), null);
  eq(toTradeRow({ ...goodDeal, volume: 999999 }, 'acc-1', 'user-1'), null);
});

test('a deal with an unreadable direction is refused', () => {
  eq(toTradeRow({ ...goodDeal, type: 'sideways' }, 'acc-1', 'user-1'), null);
});

test('a non-numeric pnl becomes a finite number, never NaN', () => {
  const row = toTradeRow({ ...goodDeal, profit: 'oops' }, 'acc-1', 'user-1')!;
  ok(Number.isFinite(row.pnl as number));
  eq(row.pnl, -4.2);
});

test('a malformed date is dropped, not invented', () => {
  const row = toTradeRow({ ...goodDeal, closeTime: 'nope' }, 'acc-1', 'user-1')!;
  eq(row.close_time, null);
});

// ---------------------------------------------------------------------------------------------
// Watermark
// ---------------------------------------------------------------------------------------------

test('the watermark is the newest stored trade time', () => {
  const rows = [
    { close_time: '2026-04-15T12:00:00.000Z' },
    { close_time: '2026-04-18T09:00:00.000Z' },
  ];
  eq(nextWatermark(rows, NOW), '2026-04-18T09:00:00.000Z');
});

test('an empty page falls back to now', () => {
  eq(nextWatermark([], NOW), new Date(NOW).toISOString());
});

// ---------------------------------------------------------------------------------------------
// Status classification
// ---------------------------------------------------------------------------------------------

test('classifies provider statuses', () => {
  eq(classifyStatus(401), 'auth');
  eq(classifyStatus(403), 'auth');
  eq(classifyStatus(429), 'rateLimit');
  eq(classifyStatus(503), 'server');
  eq(classifyStatus(400), 'other');
});

// ---------------------------------------------------------------------------------------------

if (failures.length > 0) {
  console.error(
    `\n${failures.length} failing:\n` + failures.map((f) => `  - ${f}`).join('\n'),
  );
  throw new Error(`${passed} passed, ${failures.length} failed`);
}
console.log(`sync-trades: ${passed} tests passed`);