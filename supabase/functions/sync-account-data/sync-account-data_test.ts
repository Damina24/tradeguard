// Pure-logic tests for `sync-account-data`.
//
// These need neither Deno nor credentials: they exercise the exported helpers in
// `shared.ts` only — the connection-status mapping and the position normalisation —
// so the colour rules (green ONLY for a settled live link) and the "drop an
// untrustworthy position rather than invent fields" rule are verified in CI. The
// HTTP handler needs a live Supabase project plus a MetaAPI token and is verified by
// the deploy steps in `docs/BACKEND_DEPLOY.md`.
//
// Run with:  node supabase/functions/sync-account-data/sync-account-data_test.ts
// (Node 22+ strips the types natively. `deno test` works too.)

import { mapConnection, normalisePositions, toPosition } from './shared.ts';

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

// ---------------------------------------------------------------------------------------------
// Connection mapping — the colour contract
// ---------------------------------------------------------------------------------------------

test('a settled live link maps to connected (the only green state)', () => {
  eq(mapConnection('CONNECTED'), 'connected');
  eq(mapConnection('SYNCHRONIZED'), 'connected');
});

test('a link still negotiating maps to syncing (amber, never red)', () => {
  eq(mapConnection('CONNECTING'), 'syncing');
  eq(mapConnection('SYNCHRONING'), 'syncing');
  eq(mapConnection('DEPLOYING'), 'syncing');
  eq(mapConnection('UNDEPLOYING'), 'syncing');
});

test('anything else — including absent/unknown — maps to offline (red)', () => {
  eq(mapConnection('DISCONNECTED'), 'offline');
  eq(mapConnection('DISCONNECTED_FROM_BROKER'), 'offline');
  eq(mapConnection('NOT_AUTHENTICATED'), 'offline');
  eq(mapConnection(''), 'offline');
  eq(mapConnection(undefined), 'offline');
  eq(mapConnection(null), 'offline');
  eq(mapConnection(42), 'offline');
});

test('mapping is case- and whitespace-insensitive', () => {
  eq(mapConnection('  connected  '), 'connected');
  eq(mapConnection('Connecting'), 'syncing');
});

// ---------------------------------------------------------------------------------------------
// Position normalisation — drop the untrustworthy, keep the rest
// ---------------------------------------------------------------------------------------------

test('maps a well-formed MetaAPI position (POSITION_TYPE_BUY=0)', () => {
  eq(
    toPosition({
      id: 'p1',
      symbol: 'XAUUSD',
      type: 0,
      volume: 0.5,
      openPrice: 2345.1,
      currentPrice: 2351.4,
      profit: 312,
    }),
    {
      id: 'p1',
      symbol: 'XAUUSD',
      side: 'buy',
      lots: 0.5,
      open_price: 2345.1,
      current_price: 2351.4,
      pnl: 312,
    },
  );
});

test('maps a sell position (POSITION_TYPE_SELL=1) and a word side', () => {
  eq(
    toPosition({ id: 'p2', symbol: 'eurusd', type: 1, volume: 1 })?.side,
    'sell',
  );
  eq(toPosition({ id: 'p3', symbol: 'EURUSD', side: 'sell', volume: 1 })?.side, 'sell');
  eq(toPosition({ id: 'p4', symbol: 'EURUSD', side: 'BUY', volume: 1 })?.side, 'buy');
});

test('uppercases the symbol', () => {
  eq(toPosition({ id: 'p', symbol: 'gbpjpy', type: 0, volume: 1 })?.symbol, 'GBPJPY');
});

test('drops a position with no id, symbol, side or positive size', () => {
  eq(toPosition({ symbol: 'XAUUSD', type: 0, volume: 1 }), null); // no id
  eq(toPosition({ id: 'p', type: 0, volume: 1 }), null); // no symbol
  eq(toPosition({ id: 'p', symbol: 'XAUUSD', volume: 1 }), null); // no side
  eq(toPosition({ id: 'p', symbol: 'XAUUSD', type: 0, volume: 0 }), null); // zero size
  eq(toPosition({ id: 'p', symbol: 'XAUUSD', type: 0, volume: -1 }), null); // negative
});

test('accepts alternative field names a provider might use', () => {
  eq(
    toPosition({
      positionId: 'p9',
      instrument: 'US30',
      side: 'buy',
      lots: 2,
      price: 39000,
    }),
    {
      id: 'p9',
      symbol: 'US30',
      side: 'buy',
      lots: 2,
      open_price: 39000,
      current_price: 0,
      pnl: 0,
    },
  );
});

test('normalises a bare array and a {positions:[...]} wrapper', () => {
  const one = { id: 'p', symbol: 'XAUUSD', type: 0, volume: 1 };
  eq(normalisePositions([one]).length, 1);
  eq(normalisePositions({ positions: [one, one] }).length, 2);
  eq(normalisePositions({ items: [one] }).length, 1);
});

test('skips junk entries instead of failing the whole page', () => {
  const good = { id: 'p', symbol: 'XAUUSD', type: 0, volume: 1 };
  const out = normalisePositions([good, null, 5, {}, 'nope', good]);
  eq(out.length, 2);
});

test('a non-array / malformed body yields no positions, not a throw', () => {
  eq(normalisePositions(null).length, 0);
  eq(normalisePositions('nope').length, 0);
  eq(normalisePositions({}).length, 0);
});

// ---------------------------------------------------------------------------------------------

if (failures.length > 0) {
  console.error(
    `\n${failures.length} failing:\n` + failures.map((f) => `  - ${f}`).join('\n'),
  );
  throw new Error(`${passed} passed, ${failures.length} failed`);
}
console.log(`sync-account-data: ${passed} tests passed`);
