// Pure logic for the `ai-review` Edge Function: the trade-field projection, the prompt, the
// model-response parsing and the normalisation that runs before anything is stored.
//
// Split out of `index.ts` for the same reason as `sync-trades/shared.ts` — this module touches
// neither `Deno.env` nor the network, so `ai-review_test.ts` can verify every rule (including the
// privacy allowlist) in CI without a runtime, without `OPENAI_API_KEY` and without a Supabase
// project. `index.ts` imports from here and adds only I/O.
//
// ── Security contract ────────────────────────────────────────────────────────────────────────
//   * `OPENAI_API_KEY` lives only in the function's environment. It is never logged, never
//     returned and never written to a column. Upstream error bodies are not propagated either:
//     an OpenAI error can echo the prompt back, so only the status is logged.
//   * **Nothing identifying leaves the app for the model.** `projectTradeFacts` is an ALLOWLIST,
//     not a blacklist: it copies only execution fields off our own `trades` row. Broker login,
//     account number, `metaapi_account_id`, `user_id` and `account_id` cannot reach the prompt
//     because they are never read. `FORBIDDEN_PROMPT_FIELDS` names the fields a future edit must
//     not add, and the test asserts they are absent from both the projection and the prompt.
//   * `notes` and `screenshot_url` are deliberately excluded. Free-text notes are the most likely
//     place for a trader to have typed an account number, and a screenshot URL is a Storage path.
//   * The function runs with the service role (RLS bypassed) because it must WRITE `ai_reviews`.
//     That is exactly why the trade lookup in `index.ts` filters on the caller id taken from the
//     verified JWT — never from the request body.
//   * The model is untrusted input. `normaliseReview` clamps the score, caps every string and
//     drops non-strings, so a hallucinated `score: 9999` or a 40KB string can never be persisted
//     or rendered.

export const REVIEW_MODEL = 'gpt-4o-mini';

/** Prompts are versioned in source (TRD §7). Bump when the prompt text or the JSON contract moves. */
export const PROMPT_VERSION = 'ai-review-v1';

/**
 * Fields that must never appear in the model prompt.
 *
 * This is a tripwire, not the enforcement — `projectTradeFacts` being an allowlist is the
 * enforcement. It exists so a future edit that adds `account_id` to the projection has an obvious,
 * failing test in front of it.
 */
export const FORBIDDEN_PROMPT_FIELDS = [
  'user_id',
  'account_id',
  'nickname',
  'prop_firm',
  'metaapi_account_id',
  'external_id',
  'notes',
  'screenshot_url',
  'password',
  'login',
] as const;

/** Execution facts, and the only things the model is allowed to see. */
export interface TradeFacts {
  symbol: string;
  direction: string;
  lots: number | null;
  entry: number | null;
  exit: number | null;
  sl: number | null;
  tp: number | null;
  pnl: number;
  commission: number;
  swap: number;
  r_multiple: number | null;
  session: string | null;
  setup: string | null;
  grade: string | null;
}

export interface ReviewPrompt {
  system: string;
  user: string;
}

/** Normalised, storable review. Mirrors the `ai_reviews` columns exactly. */
export interface ReviewPayload {
  summary: string;
  leak: string;
  score: number;
  suggestions: string[];
}

/** Output caps. A model that ignores the schema must not be able to blow up a card or a row. */
export const MAX_SUMMARY_CHARS = 600;
export const MAX_LEAK_CHARS = 600;
export const MAX_SUGGESTIONS = 6;
export const MAX_SUGGESTION_CHARS = 240;
export const MIN_SCORE = 0;
export const MAX_SCORE = 100;

/** A trade row too poor to review is refused rather than summarised as a fabrication. */
export function projectTradeFacts(row: Record<string, unknown> | null): TradeFacts | null {
  if (!row) return null;

  const symbol = String(row.symbol ?? '').trim().toUpperCase();
  if (symbol.length === 0) return null;

  const pnl = num(row.pnl);
  // `pnl` is NOT NULL in the schema, so a missing one is a corrupt row. Inventing 0 would let the
  // model write "closed break-even" about a trade we simply failed to read.
  if (pnl === null) return null;

  const directionRaw = String(row.direction ?? '').trim().toLowerCase();
  const direction = directionRaw === 'short' ? 'short' : directionRaw === 'long' ? 'long' : null;
  if (direction === null) return null;

  return {
    symbol,
    direction,
    lots: num(row.lots),
    entry: num(row.entry),
    exit: num(row.exit),
    sl: num(row.sl),
    tp: num(row.tp),
    pnl,
    commission: num(row.commission) ?? 0,
    swap: num(row.swap) ?? 0,
    r_multiple: num(row.rMultiple ?? row.r_multiple),
    session: text(row.session),
    setup: text(row.setup),
    grade: text(row.grade),
  };
}

/**
 * The prompt. Deterministic: the same trade always produces the same string, so a cached review
 * and a fresh one are comparable.
 *
 * The system prompt carries the compliance framing the AGENTS guardrails require — no guaranteed
 * outcomes, no "enter this trade" instruction, no performance promise — because the model is
 * writing prose a trader will act on.
 */
export function buildPrompt(facts: TradeFacts): ReviewPrompt {
  const factsBlock = [
    `symbol: ${facts.symbol}`,
    `direction: ${facts.direction}`,
    `lots: ${fmt(facts.lots)}`,
    `entry: ${fmt(facts.entry)}`,
    `exit: ${fmt(facts.exit)}`,
    `stop_loss: ${fmt(facts.sl)}`,
    `take_profit: ${fmt(facts.tp)}`,
    // Net of commission and swap, matching what the trader actually earned.
    `net_pnl: ${fmt(facts.pnl)}`,
    `commission: ${fmt(facts.commission)}`,
    `swap: ${fmt(facts.swap)}`,
    `r_multiple: ${fmt(facts.r_multiple)}`,
    `session: ${facts.session ?? 'unknown'}`,
    `setup: ${facts.setup ?? 'unknown'}`,
    `grade: ${facts.grade ?? 'ungraded'}`,
  ].join('\n');

  return {
    system: [
      'You review a single closed trade for a retail forex/gold journal and coach the trader on process.',
      'You are an educator, not a broker, advisor or signal provider.',
      'Rules you must follow:',
      '- Never promise or imply profit, a win rate, or a future outcome.',
      '- Never tell the trader to open, add to, or close a position now.',
      '- Never quote an account number, broker login, balance or credential: you have not been given them.',
      '- Judge process (was risk defined before entry, was the exit planned) separately from outcome (did it make money).',
      '- If a field is "unknown" or missing, say the data was not recorded rather than inferring it.',
      '- Return JSON only, matching the requested schema, with no prose outside it.',
    ].join('\n'),
    user: [
      'Review this closed trade. Respond with JSON only using exactly these keys:',
      '{"summary": string, "leak": string, "score": integer 0-100, "suggestions": string[]}',
      '',
      'summary: 1-3 sentences on what happened.',
      'leak: the single most likely process weakness, or "None identified."',
      'score: 0-100 execution quality. Not a profit forecast.',
      'suggestions: at most 6 short, specific, actionable process changes.',
      '',
      'Trade:',
      factsBlock,
    ].join('\n'),
  };
}

/**
 * Pulls the JSON object out of a model reply.
 *
 * `response_format: json_object` normally guarantees a bare object, but a provider can still wrap
 * it in a ```json fence or emit surrounding chatter, so the fence is stripped and the outermost
 * braces are taken. Anything that is not a JSON object returns null rather than a partial parse.
 */
export function parseModelJson(text: string | null | undefined): unknown {
  if (typeof text !== 'string') return null;
  const trimmed = text.trim();
  if (trimmed.length === 0) return null;

  const unfenced = trimmed
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/i, '')
    .trim();

  // A reply that is fundamentally an array is a contract violation, not a wrapper to unwrap.
  // Without this, the brace scan below would happily lift the FIRST OBJECT out of
  // `[{"summary":"a"},{"summary":"b"}]` and review a trade using whichever element came first —
  // silently inventing a review from a malformed response.
  if (unfenced.startsWith('[')) return null;

  const start = unfenced.indexOf('{');
  const end = unfenced.lastIndexOf('}');
  if (start === -1 || end <= start) return null;

  try {
    const parsed: unknown = JSON.parse(unfenced.slice(start, end + 1));
    return typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

/**
 * Turns whatever the model returned into a payload that is safe to store and render.
 *
 * Returns null only when there is no usable summary at all — that is a failed call, and the caller
 * must not persist an empty review that would render as though the model had nothing to say.
 * Every other field degrades to a safe default.
 */
export function normaliseReview(raw: unknown): ReviewPayload | null {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return null;
  const record = raw as Record<string, unknown>;

  const summary = clip(str(record.summary), MAX_SUMMARY_CHARS);
  if (summary.length === 0) return null;

  return {
    summary,
    leak: clip(str(record.leak), MAX_LEAK_CHARS) || 'None identified.',
    score: clampScore(record.score),
    suggestions: normaliseSuggestions(record.suggestions),
  };
}

function normaliseSuggestions(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const out: string[] = [];
  for (const entry of value) {
    // Non-strings are dropped rather than stringified: `[object Object]` in a coach's advice is
    // worse than one fewer suggestion.
    if (typeof entry !== 'string') continue;
    const clipped = clip(entry, MAX_SUGGESTION_CHARS);
    if (clipped.length === 0) continue;
    out.push(clipped);
    if (out.length >= MAX_SUGGESTIONS) break;
  }
  return out;
}

/** Coerces to a whole number inside 0..100. Anything unreadable becomes the neutral midpoint. */
export function clampScore(value: unknown): number {
  const n = num(value);
  if (n === null) return 50;
  const rounded = Math.round(n);
  if (rounded < MIN_SCORE) return MIN_SCORE;
  if (rounded > MAX_SCORE) return MAX_SCORE;
  return rounded;
}

function clip(value: string, max: number): string {
  return value.replace(/\s+/g, ' ').trim().slice(0, max);
}

function str(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

/** Finite number or null. Never NaN, never Infinity — either would poison the prompt. */
function num(value: unknown): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function text(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function fmt(value: number | null): string {
  return value === null ? 'unknown' : String(value);
}