// Pure-logic tests for `market-bars`.
//
// These need neither Deno nor credentials: they exercise the exported helpers only, so the SYMBOL
// ALLOWLIST, the provider-response normalisation, the freshness rule and the output caps are all
// verified in CI. The HTTP handler needs a live Supabase project plus a `TWELVEDATA_KEY` and is
// verified by the deploy steps in `docs/BACKEND_DEPLOY.md`.
//
// The Dart suite in `test/replay_*_test.dart` tests the client half of the same contract; the two are
// intentionally parallel.
//
// Run with:  node supabase/functions/market-bars/market-bars_test.ts
// (Node 22+ strips the types natively. `deno test` works too.)

import {
  ALLOWED_INTERVALS,
  ALLOWED_SYMBOLS,
  BARS_PER_REQUEST,
  classifyStatus,
  isAllowedInterval,
  isAllowedSymbol,
  isStale,
  MAX_BARS_PER_SERIES,
  normaliseBars,
  normaliseSymbol,
} from './shared.ts';

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

/** One provider row, in the shape TwelveData actually answers with. */
function row(dt: string, o: number, h: number, l: number, c: number) {
  return { datetime: dt, open: String(o), high: String(h), low: String(l), close: String(c) };
}

// ---------------------------------------------------------------------------------------------
// Allowlist — the metered-allowance control
// ---------------------------------------------------------------------------------------------

test('the catalogue symbols are all allowed', () => {
  for (const symbol of ALLOWED_SYMBOLS) ok(isAllowedSymbol(symbol), symbol);
});

test('symbols are matched case-insensitively and trimmed', () => {
  ok(isAllowedSymbol('xauusd'));
  ok(isAllowedSymbol('  XAUUSD  '));
  eq(normaliseSymbol('gbpusd'), 'GBPUSD');
});

test('an off-list symbol is refused', () => {
  // The regression this guards: an open symbol field would let any signed-in user spend our
  // TwelveData allowance on an arbitrary instrument, and probe what this deployment has fetched.
  ok(!isAllowedSymbol('TSLA'));
  ok(!isAllowedSymbol('AAPL'));
  ok(!isAllowedSymbol(''));
  ok(!isAllowedSymbol('XAUUSD; DROP TABLE trades'));
  ok(!isAllowedSymbol(null));
  ok(!isAllowedSymbol(42));
  ok(!isAllowedSymbol({ symbol: 'XAUUSD' }));
  eq(normaliseSymbol('TSLA'), null);
});

test('the intervals are a closed set', () => {
  for (const interval of ALLOWED_INTERVALS) ok(isAllowedInterval(interval), interval);
  ok(!isAllowedInterval('1min'));
  ok(!isAllowedInterval('1week'));
  ok(!isAllowedInterval(''));
  ok(!isAllowedInterval(null));
});

test('object rows normalise to the cached shape', () => {
  const bars = normaliseBars({
    values: [row('2024-01-02T00:00:00', 2345.5, 2350.0, 2340.0, 2348.25)],
  });
  eq(bars, [{ t: '2024-01-02T00:00:00.000Z', o: 2345.5, h: 2350, l: 2340, c: 2348.25 }]);
});

test('bars are sorted oldest first even when the provider answers newest first', () => {
  // The regression: the client walks forward in time, so a reversed series would fill at a price that
  // had not happened yet — a backtest nobody could have traded.
  const bars = normaliseBars({
    values: [
      row('2024-01-03T00:00:00', 3, 4, 2, 3.5),
      row('2024-01-01T00:00:00', 1, 2, 0.5, 1.5),
      row('2024-01-02T00:00:00', 2, 3, 1, 2.5),
    ],
  });
  eq(
    bars?.map((b) => b.c),
    [1.5, 2.5, 3.5],
  );
});

test('a duplicate timestamp is corrected, not doubled', () => {
  const bars = normaliseBars({
    values: [
      row('2024-01-02T00:00:00', 1, 2, 0.5, 1.5),
      // The restatement must itself be a well-formed bar, or it is dropped as unchartable and this
      // test would pass for the wrong reason.
      row('2024-01-02T00:00:00', 1, 10, 0.5, 9.75),
    ],
  });
  eq(bars?.length, 1);
  eq(bars?.[0].c, 9.75, 'the later restatement wins');
});

test('positional tuples parse as well as objects', () => {
  const bars = normaliseBars({
    values: [['2024-01-02T00:00:00', '1.5', '2.0', '1.0', '1.8']],
  });
  eq(bars, [{ t: '2024-01-02T00:00:00.000Z', o: 1.5, h: 2, l: 1, c: 1.8 }]);
});

test('bare daily dates are accepted', () => {
  // TwelveData sends `2024-01-02` for daily bars. Refusing it over a missing T00:00:00 would
  // silently drop the series a trader most often wants to replay.
  const bars = normaliseBars({ values: [row('2024-01-02', 1, 2, 0.5, 1.5)] });
  eq(bars?.[0].t, '2024-01-02T00:00:00.000Z');
});

test('unix epoch timestamps are accepted', () => {
  const bars = normaliseBars({ values: [row('1704153600', 1, 2, 0.5, 1.5)] });
  eq(bars?.[0].t, '2024-01-02T00:00:00.000Z');
});

test('an inconsistent bar is dropped rather than charted', () => {
  // A bar whose high is below its low is a chart the market cannot have produced, and every backtest
  // claim on screen rests on that chart.
  const bars = normaliseBars({
    values: [
      row('2024-01-02T00:00:00', 10, 1, 20, 5),
      row('2024-01-01T00:00:00', 1, 2, 0.5, 1.5),
    ],
  });
  eq(bars?.length, 1);
  eq(bars?.[0].t, '2024-01-01T00:00:00.000Z');
});

test('non-finite numbers are refused', () => {
  ok(normaliseBars({ values: [row('2024-01-02T00:00:00', 1, Infinity, 0, 1)] }) === null);
  ok(
    normaliseBars({
      values: [{ datetime: '2024-01-02', open: NaN, high: 2, low: 0, close: 1 }],
    }) === null,
  );
  ok(
    normaliseBars({
      values: [{ datetime: '2024-01-02', open: 'abc', high: 2, low: 0, close: 1 }],
    }) === null,
  );
});

test('one bad row does not cost the rest of the series', () => {
  const bars = normaliseBars({
    values: [
      row('2024-01-01T00:00:00', 1, 2, 0.5, 1.5),
      'not an object',
      row('2024-01-03T00:00:00', 3, 4, 2, 3.5),
    ],
  });
  eq(bars?.length, 2);
});

test('an unusable response is null, never an empty array', () => {
  // The handler must not cache an empty series: doing so would overwrite good cached bars with
  // nothing and the replay would lose history it already had.
  ok(normaliseBars(null) === null);
  ok(normaliseBars({}) === null);
  ok(normaliseBars({ values: [] }) === null);
  ok(normaliseBars({ values: 'nope' }) === null);
  ok(normaliseBars({ status: 'error' }) === null);
  ok(normaliseBars([null, 5, {}]) === null);
});

test('the series is capped and keeps the most recent bars', () => {
  // Every row must be internally consistent (high >= max(open, close), low <= min(open, close)), or the
  // normaliser drops it as unchartable and the cap would never actually be exercised.
  const many = Array.from({ length: MAX_BARS_PER_SERIES + 25 }, (_, i) =>
    row(new Date(Date.UTC(2024, 0, 1) + i * 3600_000).toISOString(), 100, 110, 90, 100 + (i % 7)),
  );
  const bars = normaliseBars({ values: many });
  eq(bars?.length, MAX_BARS_PER_SERIES);
  // The newest bar must survive the truncation: a replay of the recent past beats one that kept the
  // oldest window and discarded everything since.
  eq(bars?.[bars.length - 1].t, new Date(Date.UTC(2024, 0, 1) + (MAX_BARS_PER_SERIES + 24) * 3600_000).toISOString());
});

test('the request size matches the storage cap', () => {
  eq(BARS_PER_REQUEST, MAX_BARS_PER_SERIES);
});

// ---------------------------------------------------------------------------------------------
// Freshness
// ---------------------------------------------------------------------------------------------

test('a recent row is not stale', () => {
  const now = Date.parse('2024-01-02T12:00:00.000Z');
  ok(!isStale('2024-01-02T10:00:00.000Z', now, 6 * 3600_000));
});

test('a row older than the window is stale', () => {
  const now = Date.parse('2024-01-02T12:00:00.000Z');
  ok(isStale('2024-01-02T01:00:00.000Z', now, 6 * 3600_000));
});

test('an absent or unparseable stamp counts as stale', () => {
  // A row whose age cannot be established is not one to present as current.
  const now = Date.parse('2024-01-02T12:00:00.000Z');
  ok(isStale(null, now, 6 * 3600_000));
  ok(isStale('not a date', now, 6 * 3600_000));
  ok(isStale('', now, 6 * 3600_000));
});

test('a future stamp is not treated as stale', () => {
  // Clock skew between us and the writer must not trigger an endless refresh loop on a metered key.
  const now = Date.parse('2024-01-02T12:00:00.000Z');
  ok(!isStale('2024-01-02T12:30:00.000Z', now, 6 * 3600_000));
});

// ---------------------------------------------------------------------------------------------
// Failure vocabulary
// ---------------------------------------------------------------------------------------------

test('provider statuses map onto the closed set', () => {
  eq(classifyStatus(404), 'unknownSymbol');
  eq(classifyStatus(429), 'rateLimit');
  eq(classifyStatus(500), 'server');
  eq(classifyStatus(503), 'server');
  eq(classifyStatus(400), 'server');
});

// ---------------------------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------------------------

if (failures.length > 0) {
  console.error(`market-bars: ${failures.length} of ${passed + failures.length} failed`);
  for (const failure of failures) console.error(`  ✗ ${failure}`);
  process.exit(1);
}
console.log(`market-bars: ${passed} passed`);