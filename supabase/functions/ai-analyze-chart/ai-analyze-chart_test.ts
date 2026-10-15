// Pure-logic tests for the `ai-analyze-chart` Edge Function.
import {
  ANALYSIS_MODEL,
  buildPrompt,
  isOwnImagePath,
  mimeForPath,
  normaliseAnalysis,
  parseModelJson,
  PROMPT_VERSION,
} from './shared.ts';

let passed = 0;
const failures: string[] = [];

function test(name: string, fn: () => void): void {
  try {
    fn();
    passed++;
  } catch (err) {
    failures.push(`${name}: ${err instanceof Error ? err.message : err}`);
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

test('ownership accepts own path', () => {
  eq(isOwnImagePath('user-a/chart.png', 'user-a'), true);
});

test('ownership rejects siblings and traversal', () => {
  eq(isOwnImagePath('user-a/other.png', 'user-b'), false);
  eq(isOwnImagePath('user-a/../../etc/passwd', 'user-a'), false);
  eq(isOwnImagePath('/etc/passwd', 'user-a'), false);
  eq(isOwnImagePath('chart.png', 'user-a'), false);
});

test('mime allows png jpg webp only', () => {
  eq(mimeForPath('a.png'), 'image/png');
  eq(mimeForPath('a.jpg'), 'image/jpeg');
  eq(mimeForPath('a.gif'), null);
});

test('prompt carries compliance framing', () => {
  const p = buildPrompt();
  ok(p.system.toLowerCase().includes('profit'));
  ok(!p.system.includes('enter here'));
});

test('parser extracts fenced json and refuses arrays', () => {
  const parsed = parseModelJson('```json\n{"bias":"bullish"}\n```');
  eq((parsed as Record<string, unknown>).bias, 'bullish');
  eq(parseModelJson('[1,2,3]'), null);
});

test('normalise keeps valid and caps lists', () => {
  const result = normaliseAnalysis({
    bias: 'bullish',
    levels: [100.0, 101.5],
    entry: 100.5,
    sl: 99.0,
    tp: [101.0, 102.0],
    note: 'Valid analysis',
  });
  ok(result !== null);
  eq(result!.levels, [100.0, 101.5]);
  eq(normaliseAnalysis({ bias: 'neutral', levels: [] }), null);
  const capped = normaliseAnalysis({
    bias: 'neutral',
    levels: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    note: 'x'.repeat(500),
  })!;
  eq(capped.levels.length, 6);
  eq(capped.note.length, 400);
});

test('metadata pins model and prompt version', () => {
  eq(ANALYSIS_MODEL, 'YOUR_AI_MODEL_NAME');
  ok(PROMPT_VERSION.length > 0);
});

if (failures.length > 0) {
  console.error(`\n${failures.length} failing:\n` + failures.join('\n'));
  throw new Error(`${passed} passed, ${failures.length} failed`);
}
console.log(`ai-analyze-chart: ${passed} tests passed`);
