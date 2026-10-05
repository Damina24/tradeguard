// Pure-logic tests for `ai-review`.
//
// These need neither Deno nor credentials: they exercise the exported helpers only, so the
// PRIVACY ALLOWLIST, the prompt contract, the model's-output normalisation and the failure
// behaviour are all verified in CI. The HTTP handler needs a live Supabase project plus an
// `OPENAI_API_KEY` and is verified by the deploy steps in `docs/BACKEND_DEPLOY.md`.
//
// The Dart suite in `test/ai_review_*_test.dart` tests the client half of the same contract; the
// two are intentionally parallel.
//
// Run with:  node supabase/functions/ai-review/ai-review_test.ts
// (Node 22+ strips the types natively. `deno test` works too.)

import {
  buildPrompt,
  clampScore,
  FORBIDDEN_PROMPT_FIELDS,
  MAX_LEAK_CHARS,
  MAX_SUGGESTION_CHARS,
  MAX_SUGGESTIONS,
  MAX_SUMMARY_CHARS,
  normaliseReview,
  parseModelJson,
  projectTradeFacts,
  PROMPT_VERSION,
  REVIEW_MODEL,
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

const UUID = '11111111-2222-3333-4444-555555555555';

function goodRow(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: UUID,
    user_id: 'user-a',
    account_id: 'acc-a',
    symbol: 'XAUUSD',
    direction: 'long',
    lots: 0.5,
    entry: 2345.5,
    exit: 2360.25,
    sl: 2338.0,
    tp: 2360.0,
    pnl: 412.5,
    commission: -3.5,
    swap: -1.25,
    session: 'london',
    setup: 'Breakout',
    grade: 'B',
    ...over,
  };
}

// ---------------------------------------------------------------------------------------------
// Projection — the privacy allowlist
// ---------------------------------------------------------------------------------------------

test('a complete row projects every execution field', () => {
  const facts = projectTradeFacts(goodRow())!;
  eq(facts.symbol, 'XAUUSD');
  eq(facts.direction, 'long');
  eq(facts.pnl, 412.5);
  eq(facts.commission, -3.5);
  eq(facts.session, 'london');
  eq(facts.grade, 'B');
});

test('the symbol is upper-cased', () => {
  eq(projectTradeFacts(goodRow({ symbol: 'eurusd' }))!.symbol, 'EURUSD');
});

test('no forbidden field survives the projection', () => {
  const facts = projectTradeFacts(goodRow()) as unknown as Record<string, unknown>;
  for (const field of FORBIDDEN_PROMPT_FIELDS) {
    ok(!(field in facts), `${field} must not be projected`);
  }
});

test('no forbidden value appears in the prompt', () => {
  const row = goodRow({
    nickname: 'FTMO EVAL 100K',
    metaapi_account_id: 'meta-secret-123',
    external_id: 'deal-999',
    notes: 'my broker login is 8812345',
    screenshot_url: 'https://storage.example/tradeguard/user-a/shot.png',
  });
  const prompt = buildPrompt(projectTradeFacts(row)!);
  const haystack = (prompt.system + '\n' + prompt.user).toLowerCase();

  for (const secret of [
    'ftmo eval',
    'meta-secret-123',
    'deal-999',
    '8812345',
    'storage.example',
    'user-a',
    'acc-a',
  ]) {
    ok(!haystack.includes(secret), `prompt must not contain "${secret}"`);
  }
});

test('an identifier column named like a forbidden field is never read', () => {
  // A hostile or typo'd column must not sneak in: the projection reads named fields only.
  const facts = projectTradeFacts(
    goodRow({ metaapi_account_id: 'leak', password: 'leak', login: 'leak' }),
  ) as unknown as Record<string, unknown>;
  eq(facts.metaapi_account_id, undefined);
  eq(facts.password, undefined);
  eq(facts.login, undefined);
});

test('a row with no symbol is refused', () => {
  eq(projectTradeFacts(goodRow({ symbol: '' })), null);
  eq(projectTradeFacts(goodRow({ symbol: undefined })), null);
});

test('a row with no pnl is refused rather than read as break-even', () => {
  eq(projectTradeFacts(goodRow({ pnl: undefined })), null);
  eq(projectTradeFacts(goodRow({ pnl: null })), null);
  eq(projectTradeFacts(goodRow({ pnl: 'oops' })), null);
});

test('a row with an unreadable direction is refused', () => {
  eq(projectTradeFacts(goodRow({ direction: 'sideways' })), null);
  eq(projectTradeFacts(goodRow({ direction: null })), null);
});

test('a null row is refused', () => {
  eq(projectTradeFacts(null), null);
});

test('optional prices are null, not zero', () => {
  const facts = projectTradeFacts(goodRow({ sl: null, tp: null }))!;
  eq(facts.sl, null);
  eq(facts.tp, null);
});

test('a numeric string is coerced, an infinite one is not', () => {
  eq(projectTradeFacts(goodRow({ entry: '1.0850' }))!.entry, 1.085);
  eq(projectTradeFacts(goodRow({ entry: Infinity }))!.entry, null);
  eq(projectTradeFacts(goodRow({ entry: NaN }))!.entry, null);
});

test('missing costs default to zero, never null', () => {
  const facts = projectTradeFacts(goodRow({ commission: undefined, swap: null }))!;
  eq(facts.commission, 0);
  eq(facts.swap, 0);
});

test('a blank session or setup becomes null, not an empty string', () => {
  const facts = projectTradeFacts(goodRow({ session: '   ', setup: '' }))!;
  eq(facts.session, null);
  eq(facts.setup, null);
});

// ---------------------------------------------------------------------------------------------
// Prompt contract
// ---------------------------------------------------------------------------------------------

test('the prompt is deterministic for the same trade', () => {
  const a = buildPrompt(projectTradeFacts(goodRow())!);
  const b = buildPrompt(projectTradeFacts(goodRow())!);
  eq(a.user, b.user);
  eq(a.system, b.system);
});

test('a different trade produces a different prompt', () => {
  const a = buildPrompt(projectTradeFacts(goodRow())!);
  const b = buildPrompt(projectTradeFacts(goodRow({ pnl: -412.5, direction: 'short' }))!);
  ok(a.user !== b.user);
});

test('an absent field is stated as unknown, never guessed', () => {
  const facts = projectTradeFacts(goodRow({ sl: null, session: null, setup: null, grade: null }))!;
  const prompt = buildPrompt(facts);
  ok(prompt.user.includes('stop_loss: unknown'));
  ok(prompt.user.includes('session: unknown'));
  ok(prompt.user.includes('setup: unknown'));
  ok(prompt.user.includes('grade: ungraded'));
});

test('the prompt forbids profit promises and trade instructions', () => {
  const prompt = buildPrompt(projectTradeFacts(goodRow())!);
  const system = prompt.system.toLowerCase();
  ok(system.includes('never promise'));
  ok(system.includes('never tell the trader to open'));
  ok(system.includes('educator'));
});

test('the prompt asks for the documented JSON contract', () => {
  const prompt = buildPrompt(projectTradeFacts(goodRow())!);
  for (const key of ['"summary"', '"leak"', '"score"', '"suggestions"']) {
    ok(prompt.user.includes(key), `prompt must request ${key}`);
  }
});

test('the net pnl is sent as stored, not recomputed', () => {
  const prompt = buildPrompt(projectTradeFacts(goodRow({ pnl: 412.5 }))!);
  ok(prompt.user.includes('net_pnl: 412.5'));
});

// ---------------------------------------------------------------------------------------------
// Model response parsing
// ---------------------------------------------------------------------------------------------

test('a bare JSON object parses', () => {
  const parsed = parseModelJson('{"summary":"ok","leak":"none","score":70,"suggestions":[]}');
  eq((parsed as Record<string, unknown>).score, 70);
});

test('a fenced JSON block parses', () => {
  const parsed = parseModelJson('```json\n{"summary":"ok","score":70}\n```');
  eq((parsed as Record<string, unknown>).summary, 'ok');
});

test('a prose-wrapped object parses', () => {
  const parsed = parseModelJson('Sure! Here you go: {"summary":"ok"} — hope that helps.');
  eq((parsed as Record<string, unknown>).summary, 'ok');
});

test('a top-level array is not an object', () => {
  eq(parseModelJson('[{"summary":"ok"}]'), null);
});

test('a multi-element array is refused rather than unwrapped', () => {
  // Regression: the brace scan must not lift element 0 out of a malformed array reply and pass
  // it off as a real review.
  eq(parseModelJson('[{"summary":"first"},{"summary":"second"}]'), null);
  eq(parseModelJson('```json\n[{"summary":"first"}]\n```'), null);
});

test('unparseable text is null, not a partial read', () => {
  eq(parseModelJson('not json at all'), null);
  eq(parseModelJson('{ broken: '), null);
});

test('an empty or non-string reply is null', () => {
  eq(parseModelJson(''), null);
  eq(parseModelJson('   '), null);
  eq(parseModelJson(null), null);
  eq(parseModelJson(undefined), null);
});

// ---------------------------------------------------------------------------------------------
// Normalisation — the model is untrusted
// ---------------------------------------------------------------------------------------------

test('a well-formed payload passes through unchanged', () => {
  const review = normaliseReview({
    summary: 'Clean winner.',
    leak: 'Moved the stop.',
    score: 72,
    suggestions: ['Set the stop before entry.'],
  })!;
  eq(review.score, 72);
  eq(review.suggestions, ['Set the stop before entry.']);
});

test('a payload with no summary is a failure, not an empty review', () => {
  eq(normaliseReview({ leak: 'x', score: 50, suggestions: [] }), null);
  eq(normaliseReview({ summary: '   ', score: 50 }), null);
  eq(normaliseReview({ summary: 42 }), null);
});

test('a non-object payload is refused', () => {
  eq(normaliseReview(null), null);
  eq(normaliseReview('a string'), null);
  eq(normaliseReview([1, 2]), null);
});

test('the score is clamped to 0..100', () => {
  eq(clampScore(9999), 100);
  eq(clampScore(-5), 0);
  eq(clampScore(0), 0);
  eq(clampScore(100), 100);
});

test('a fractional score is rounded, and a non-numeric one is neutral', () => {
  eq(clampScore(67.6), 68);
  eq(clampScore('80'), 80);
  eq(clampScore('high'), 50);
  eq(clampScore(null), 50);
  eq(clampScore(undefined), 50);
  eq(clampScore(NaN), 50);
});

test('a missing leak becomes an explicit "none identified"', () => {
  eq(normaliseReview({ summary: 'ok' })!.leak, 'None identified.');
  eq(normaliseReview({ summary: 'ok', leak: '  ' })!.leak, 'None identified.');
});

test('over-long text is capped', () => {
  const review = normaliseReview({
    summary: 'a'.repeat(MAX_SUMMARY_CHARS + 500),
    leak: 'b'.repeat(MAX_LEAK_CHARS + 500),
    suggestions: ['c'.repeat(MAX_SUGGESTION_CHARS + 500)],
    score: 50,
  })!;
  eq(review.summary.length, MAX_SUMMARY_CHARS);
  eq(review.leak.length, MAX_LEAK_CHARS);
  eq(review.suggestions[0].length, MAX_SUGGESTION_CHARS);
});

test('whitespace in a field is collapsed to single spaces', () => {
  eq(normaliseReview({ summary: 'a\n\n  b   c', score: 50 })!.summary, 'a b c');
});

test('suggestions are capped in count', () => {
  const many = Array.from({ length: 40 }, (_, i) => `tip ${i}`);
  const review = normaliseReview({ summary: 'ok', suggestions: many })!;
  eq(review.suggestions.length, MAX_SUGGESTIONS);
});

test('a non-array suggestions field yields no suggestions', () => {
  eq(normaliseReview({ summary: 'ok', suggestions: 'do this' })!.suggestions, []);
  eq(normaliseReview({ summary: 'ok', suggestions: { a: 1 } })!.suggestions, []);
});

test('non-string suggestions are dropped, not stringified', () => {
  const review = normaliseReview({
    summary: 'ok',
    suggestions: ['good tip', 42, null, { a: 1 }, '   ', 'other tip'],
  })!;
  eq(review.suggestions, ['good tip', 'other tip']);
});

test('a sparse payload survives the full parse + normalise path', () => {
  const review = normaliseReview(parseModelJson('{"summary":"ok","score":10}'));
  eq(review!.score, 10);
  eq(review!.suggestions, []);
});

// ---------------------------------------------------------------------------------------------
// Metadata
// ---------------------------------------------------------------------------------------------

test('the model is the documented one', () => {
  eq(REVIEW_MODEL, 'gpt-4o-mini');
});

test('the prompt version is recorded', () => {
  ok(PROMPT_VERSION.length > 0);
  ok(PROMPT_VERSION.includes('v'));
});

// ---------------------------------------------------------------------------------------------

if (failures.length > 0) {
  console.error(
    `\n${failures.length} failing:\n` + failures.map((f) => `  - ${f}`).join('\n'),
  );
  throw new Error(`${passed} passed, ${failures.length} failed`);
}
console.log(`ai-review: ${passed} tests passed`);