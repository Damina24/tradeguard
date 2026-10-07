// Pure-logic tests for `copy-signal`.
//
// These need neither Deno nor credentials: they exercise the exported helpers only, so the PAPER
// DEFAULT, the kill switch, the live-consent gate, the per-account permission, the max-lots cap,
// the concurrent cap and the riskΓåÆlots math are all verified in CI. The HTTP handler needs a live
// Supabase project plus a `METAAPI_TOKEN` and is verified by the deploy steps in
// `docs/BACKEND_DEPLOY.md`.
//
// The Dart suite in `test/copy_*_test.dart` tests the client half of the same contract ΓÇö the
// PARITY FIXTURES below are duplicated there verbatim, so a formula change that lands on one side
// only fails both suites.
//
// Run with:  node supabase/functions/copy-signal/copy_signal_test.ts
// (Node 22+ strips the types natively. `deno test` works too.)

import {
  DEFAULT_MAX_CONCURRENT_FOLLOWS,
  DEFAULT_MAX_LOTS,
  DEFAULT_RISK_PCT,
  MAX_ACCOUNTS_PER_REQUEST,
  MAX_RISK_PCT,
  MIN_RISK_PCT,
  clampRiskPct,
  evaluateAccount,
  lotSize,
  normalizeMode,
  pipsBetween,
  pipValue,
  validateBody,
} from './shared.ts';
import type { AccountCtx, SettingsCtx, SignalCtx } from './shared.ts';

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

/** Float-noise-tolerant equality. `pipsBetween` is pure IEEE-754 arithmetic ΓÇö Dart's
 * `(to - from).abs() * factor` produces the same last-bit noise ΓÇö so pip distances are asserted
 * to 1e-6 while the 2dp lot values stay exact. */
function near(actual: number, expected: number, note = ''): void {
  if (!Number.isFinite(actual) || Math.abs(actual - expected) > 1e-6) {
    throw new Error(`expected ~${expected} ${note}, got ${actual}`);
  }
}

const SIGNAL_ID = '11111111-2222-3333-4444-555555555555';
const ACCOUNT_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

const signal: SignalCtx = { status: 'active', entry: 2345.5, sl: 2338.0, tp1: 2358.0 };

function account(over: Partial<AccountCtx> = {}): AccountCtx {
  return {
    id: ACCOUNT_ID,
    equity: 100000,
    copyEnabled: true,
    metaapiAccountId: 'meta-123',
    ...over,
  };
}

const settings: SettingsCtx = {
  liveConsent: false,
  killSwitch: false,
  maxLots: DEFAULT_MAX_LOTS,
  maxConcurrentFollows: DEFAULT_MAX_CONCURRENT_FOLLOWS,
};

// ---------------------------------------------------------------------------------------------
// Parity fixtures ΓÇö IDENTICAL table in test/copy_policy_test.dart
// ---------------------------------------------------------------------------------------------

test('parity: XAUUSD 75-pip stop, $100k, 1% risk -> 1.33 lots', () => {
  eq(lotSize({ balance: 100000, riskPct: 1, symbol: 'XAUUSD', stopPips: 75 }), 1.33);
});

test('parity: EURUSD 50-pip stop, $50k, 2% risk -> 2.00 lots', () => {
  eq(lotSize({ balance: 50000, riskPct: 2, symbol: 'EURUSD', stopPips: 50 }), 2);
});

test('parity: USDJPY 30-pip stop, $10k, 0.5% risk -> 0.19 lots', () => {
  eq(lotSize({ balance: 10000, riskPct: 0.5, symbol: 'USDJPY', stopPips: 30 }), 0.19);
});

test('parity: XAUUSD entry/stop distance uses the gold pip factor', () => {
  near(pipsBetween('XAUUSD', 2345.5, 2338.0), 75, '(XAUUSD)');
  near(pipsBetween('EURUSD', 1.1000, 1.0950), 50, '(EURUSD)');
  near(pipsBetween('USDJPY', 150.00, 149.70), 30, '(USDJPY)');
});

test('pip values match the documented table', () => {
  eq(pipValue('XAUUSD'), 10);
  eq(pipValue('USDJPY'), 9);
  eq(pipValue('XAGUSD'), 50);
  eq(pipValue('EURUSD'), 10);
});

test('degenerate inputs size to zero, never negative', () => {
  eq(lotSize({ balance: 100000, riskPct: 1, symbol: 'XAUUSD', stopPips: 0 }), 0);
  eq(lotSize({ balance: 100000, riskPct: 1, symbol: 'XAUUSD', stopPips: -5 }), 0);
  eq(lotSize({ balance: 0, riskPct: 1, symbol: 'XAUUSD', stopPips: 75 }), 0);
  eq(lotSize({ balance: 100000, riskPct: 0, symbol: 'XAUUSD', stopPips: 75 }), 0);
});

// ---------------------------------------------------------------------------------------------
// Mode: paper is the default, live is never inferred
// ---------------------------------------------------------------------------------------------

test('mode defaults to paper for anything that is not the exact string "live"', () => {
  eq(normalizeMode(undefined), 'paper');
  eq(normalizeMode(null), 'paper');
  eq(normalizeMode(''), 'paper');
  eq(normalizeMode('LIVE'), 'paper');
  eq(normalizeMode('live '), 'paper');
  eq(normalizeMode(true), 'paper');
  eq(normalizeMode({ mode: 'live' }), 'paper');
  eq(normalizeMode('live'), 'live');
});

test('risk_pct clamps instead of failing', () => {
  eq(clampRiskPct(undefined), DEFAULT_RISK_PCT);
  eq(clampRiskPct('not a number'), DEFAULT_RISK_PCT);
  eq(clampRiskPct(0.01), MIN_RISK_PCT);
  eq(clampRiskPct(99), MAX_RISK_PCT);
  eq(clampRiskPct(1.234), 1.23);
  eq(clampRiskPct('2.5'), 2.5);
});

test('validateBody accepts a well-formed request and dedupes accounts', () => {
  const r = validateBody({
    signal_id: SIGNAL_ID,
    account_ids: [ACCOUNT_ID, ACCOUNT_ID],
    risk_pct: 2,
    mode: 'paper',
  });
  ok(r.ok);
  if (!r.ok) return;
  eq(r.body.accountIds, [ACCOUNT_ID]);
  eq(r.body.riskPct, 2);
  eq(r.body.mode, 'paper');
});

test('validateBody refuses the shapes that cannot be honoured', () => {
  eq(validateBody(null).ok, false);
  eq(validateBody({}).ok, false);
  eq(validateBody({ signal_id: 'not-a-uuid' }).ok, false);
  eq(validateBody({ signal_id: SIGNAL_ID }).ok, false);
  eq(validateBody({ signal_id: SIGNAL_ID, account_ids: [] }).ok, false);
  eq(validateBody({ signal_id: SIGNAL_ID, account_ids: ['nope'] }).ok, false);
  const many = Array.from(
    { length: MAX_ACCOUNTS_PER_REQUEST + 1 },
    (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`,
  );
  eq(validateBody({ signal_id: SIGNAL_ID, account_ids: many }).ok, false);
});

// ---------------------------------------------------------------------------------------------
// evaluateAccount ΓÇö the guardrail ladder
// ---------------------------------------------------------------------------------------------

test('paper follows an enabled account without any consent', () => {
  const v = evaluateAccount({
    pair: 'XAUUSD',
    signal,
    account: account(),
    settings,
    requestedMode: 'paper',
    riskPct: 1,
    openFollows: 0,
  });
  eq(v.refusal, null);
  eq(v.mode, 'paper');
  eq(v.lots, 1.33); // 100000 ├ù 1% / (75 pips ├ù $10) = 1.3333ΓÇª ΓåÆ 1.33
  eq(v.riskPips, 75);
});

test('the kill switch blocks paper AND live, before every other rule', () => {
  const v = evaluateAccount({
    pair: 'XAUUSD',
    signal,
    account: account({ copyEnabled: false }),
    settings: { ...settings, killSwitch: true, liveConsent: true },
    requestedMode: 'paper',
    riskPct: 1,
    openFollows: 99,
  });
  eq(v.refusal, 'killSwitch');
  eq(v.lots, 0);
});

test('live without stored consent is refused, never downgraded to paper', () => {
  const v = evaluateAccount({
    pair: 'XAUUSD',
    signal,
    account: account(),
    settings, // liveConsent: false
    requestedMode: 'live',
    riskPct: 1,
    openFollows: 0,
  });
  eq(v.refusal, 'consentRequired');
  eq(v.mode, 'live'); // the request stays live in the response; nothing was simulated
  eq(v.lots, 0);
});

test('live with consent, permission and a link passes', () => {
  const v = evaluateAccount({
    pair: 'XAUUSD',
    signal,
    account: account(),
    settings: { ...settings, liveConsent: true },
    requestedMode: 'live',
    riskPct: 1,
    openFollows: 0,
  });
  eq(v.refusal, null);
  eq(v.mode, 'live');
});

test('live without a MetaAPI link is refused even with consent', () => {
  const v = evaluateAccount({
    pair: 'XAUUSD',
    signal,
    account: account({ metaapiAccountId: null }),
    settings: { ...settings, liveConsent: true },
    requestedMode: 'live',
    riskPct: 1,
    openFollows: 0,
  });
  eq(v.refusal, 'noMetaapiLink');
});

test('an account without per-account permission is refused in both modes', () => {
  for (const mode of ['paper', 'live'] as const) {
    const v = evaluateAccount({
      pair: 'XAUUSD',
      signal,
      account: account({ copyEnabled: false }),
      settings: { ...settings, liveConsent: true },
      requestedMode: mode,
      riskPct: 1,
      openFollows: 0,
    });
    eq(v.refusal, 'accountDisabled');
  }
});

test('an account id that is not the caller\'s is accountMissing ΓÇö same as nonexistent', () => {
  const v = evaluateAccount({
    pair: 'XAUUSD',
    signal,
    account: account(),
    settings,
    requestedMode: 'paper',
    riskPct: 1,
    openFollows: 0,
    accountExists: false,
  });
  eq(v.refusal, 'accountMissing');
});

test('an inactive signal cannot be followed at all', () => {
  for (const status of ['closed', 'cancelled', '']) {
    const v = evaluateAccount({
      pair: 'XAUUSD',
      signal: { ...signal, status },
      account: account(),
      settings,
      requestedMode: 'paper',
      riskPct: 1,
      openFollows: 0,
    });
    eq(v.refusal, 'inactiveSignal');
  }
});

test('a zero-width stop is invalidSignal, not a maximum-size order', () => {
  const v = evaluateAccount({
    pair: 'XAUUSD',
    signal: { ...signal, sl: signal.entry },
    account: account(),
    settings,
    requestedMode: 'paper',
    riskPct: 1,
    openFollows: 0,
  });
  eq(v.refusal, 'invalidSignal');
  eq(v.riskPips, 0);
  eq(v.lots, 0);
});

test('lots over the cap are refused, not silently clamped', () => {
  const v = evaluateAccount({
    pair: 'XAUUSD',
    signal,
    account: account({ equity: 1000000 }), // 1% = $10k risk over a 750/lot stop = 13.33 lots
    settings: { ...settings, maxLots: 5 },
    requestedMode: 'paper',
    riskPct: 1,
    openFollows: 0,
  });
  eq(v.refusal, 'maxLots');
  eq(v.lots, 13.33); // the refused size is reported so the sheet can say WHY
});

test('the concurrent cap refuses once open follows reach the limit', () => {
  const v = evaluateAccount({
    pair: 'XAUUSD',
    signal,
    account: account(),
    settings: { ...settings, maxConcurrentFollows: 3 },
    requestedMode: 'paper',
    riskPct: 1,
    openFollows: 3,
  });
  eq(v.refusal, 'maxConcurrent');
});

test('the concurrent cap allows one more slot exactly at limit-1', () => {
  const v = evaluateAccount({
    pair: 'XAUUSD',
    signal,
    account: account(),
    settings: { ...settings, maxConcurrentFollows: 3 },
    requestedMode: 'paper',
    riskPct: 1,
    openFollows: 2,
  });
  eq(v.refusal, null);
});

test('a refused result never carries a positive size', () => {
  const cases = evaluateAccount({
    pair: 'XAUUSD',
    signal,
    account: account({ copyEnabled: false }),
    settings: { ...settings, killSwitch: true },
    requestedMode: 'paper',
    riskPct: 1,
    openFollows: 0,
  });
  eq(cases.lots, 0);
});

// ---------------------------------------------------------------------------------------------

if (failures.length > 0) {
  console.error(
    `\n${failures.length} failing:\n` + failures.map((f) => `  - ${f}`).join('\n'),
  );
  throw new Error(`${passed} passed, ${failures.length} failed`);
}
console.log(`copy-signal: ${passed} tests passed`);
