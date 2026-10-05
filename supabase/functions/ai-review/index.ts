// ai-review — HTTP (auth), per `docs/BACKEND_SCHEMA.md`.
//
//   POST /functions/v1/ai-review  {trade_id} -> {summary, leak, score, suggestions[]}
//
// Reviews ONE closed trade: reads our own `trades` row, asks OpenAI `gpt-4o-mini` for a coaching
// note in a fixed JSON shape, stores it in `ai_reviews`, and returns it.
//
// All policy — the field allowlist, the prompt, the parsing and the normalisation — lives in
// `./shared.ts` so `ai-review_test.ts` can verify it without a runtime, without `OPENAI_API_KEY`
// and without a Supabase project. This file adds only I/O.
//
// ── Authorization ─────────────────────────────────────────────────────────────────────────────
// This function is USER-facing, not cron: a trader taps "Get AI review" on their own trade. So the
// gate is the opposite shape to `guard-check` / `sync-trades`, which require the SERVICE-role bearer
// because a scheduler has no user session.
//
//   * `verify_jwt = true` (config.toml) makes the platform reject anonymous calls.
//   * We then RESOLVE the caller with GoTrue using the caller's own bearer token and read
//     `trades.user_id` off the row the DATABASE returns.
//   * The write uses the service role (the user's JWT could not insert an `ai_reviews` row once
//     migration 0007 narrows that policy to SELECT). Because the service role bypasses RLS, the
//     ownership check is explicit and unavoidable: `.eq('user_id', caller.id)` on the read, and the
//     same id on the insert. `user_id` is NEVER read from the request body — a body that carries
//     one is ignored, so there is no IDOR for a caller to attempt.
//
// ── Secrets ────────────────────────────────────────────────────────────────────────────────────
//   OPENAI_API_KEY     required — without it the function returns 503 `notConfigured`, it does not
//                       fabricate a review. SUPABASE_* come from the platform.
//
// Not covered by `flutter test`: this needs a live Supabase project and an `OPENAI_API_KEY`. The
// security rules it depends on are unit-tested in `ai-review_test.ts` and the client half in
// `test/ai_review_repository_test.dart`.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
  PROMPT_VERSION,
  REVIEW_MODEL,
  buildPrompt,
  normaliseReview,
  parseModelJson,
  projectTradeFacts,
} from './shared.ts';
import type { ReviewPayload, TradeFacts } from './shared.ts';

const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';

type AnyRecord = Record<string, unknown>;

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function serviceClient() {
  const key = Deno.env.get('SUPABASE_SERVICE_KEY');
  const url = Deno.env.get('SUPABASE_URL');
  if (!key || !url) throw new Error('SUPABASE_SERVICE_KEY / SUPABASE_URL is not set');
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * The caller's user id, resolved from their own bearer token.
 *
 * `SUPABASE_URL` + the ANON key are used only to ask GoTrue who this token belongs to — no query
 * is run as the caller and nothing is written. Returns null when the token is absent or invalid,
 * which the handler turns into a 401.
 */
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
 * One completion from OpenAI, or a failure classification.
 *
 * The key is read from the environment and used for exactly one header on exactly one request; it
 * is never logged and never returned. A non-2xx logs the STATUS ONLY: an OpenAI error body echoes
 * the prompt, which contains this trader's own execution data.
 */
async function askModel(prompt: { system: string; user: string }): Promise<
  { content: string } | { failure: string }
> {
  const key = Deno.env.get('OPENAI_API_KEY');
  if (!key) return { failure: 'notConfigured' };

  let res: Response;
  try {
    res = await fetch(OPENAI_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        model: REVIEW_MODEL,
        temperature: 0.2,
        // Deterministic-ish and schema-bound. A review describes what already happened rather than
        // being a creative task, so the lowest useful sampling keeps two reviews of one trade
        // comparable.
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: prompt.system },
          { role: 'user', content: prompt.user },
        ],
      }),
    });
  } catch {
    console.error('ai-review: model unreachable');
    return { failure: 'network' };
  }

  if (!res.ok) {
    console.error('ai-review: model rejected', res.status);
    return { failure: res.status === 429 ? 'rateLimit' : 'server' };
  }

  let body: unknown;
  try {
    body = await res.json();
  } catch {
    return { failure: 'malformed' };
  }

  const content = (body as AnyRecord)?.choices?.[0]?.message?.content;
  if (typeof content !== 'string') return { failure: 'malformed' };
  return { content };
}

/** A uuid, or null. Anything else is a bad request rather than a query. */
function tradeIdFrom(body: unknown): string | null {
  if (typeof body !== 'object' || body === null) return null;
  const id = (body as AnyRecord).trade_id;
  if (typeof id !== 'string') return null;
  const trimmed = id.trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(trimmed)) {
    return null;
  }
  return trimmed.toLowerCase();
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed' }, 405);

  const userId = await callerId(req.headers.get('Authorization'));
  if (userId === null) return json({ ok: false, error: 'Unauthorized' }, 401);

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'Invalid body' }, 400);
  }

  const tradeId = tradeIdFrom(body);
  if (tradeId === null) return json({ ok: false, error: 'trade_id is required' }, 400);

  // deno-lint-ignore no-explicit-any
  let sb: any;
  try {
    sb = serviceClient();
  } catch (err) {
    console.error('ai-review: service client unavailable', String(err));
    return json({ ok: false, error: 'notConfigured' }, 503);
  }

  // Ownership is part of the WHERE clause, not a check after the read. A trade belonging to another
  // user is simply not returned, and a missing trade is a 404 — identical to a trade that does not
  // exist, so this endpoint cannot be used to probe for another trader's trade ids.
  //
  // The projection is an ALLOWLIST, so `notes`, `screenshot_url` and every identifier stay in the
  // database even though this query runs with the service role.
  const { data: tradeRows, error: tradeError } = await sb
    .from('trades')
    .select('symbol,direction,lots,entry,exit,sl,tp,pnl,commission,swap,session,setup,grade')
    .eq('id', tradeId)
    .eq('user_id', userId)
    .limit(1);

  if (tradeError) {
    console.error('ai-review: trade read failed');
    return json({ ok: false, error: 'server' }, 500);
  }

  const row = ((tradeRows ?? []) as AnyRecord[])[0] ?? null;
  if (row === null) return json({ ok: false, error: 'Trade not found' }, 404);

  const facts: TradeFacts | null = projectTradeFacts(row);
  if (facts === null) {
    // The row exists but is too incomplete to describe. Saying so is honest; asking the model to
    // fill the gaps would invent a trade.
    return json({ ok: false, error: 'Trade is too incomplete to review' }, 422);
  }

  const answer = await askModel(buildPrompt(facts));
  if ('failure' in answer) {
    return json({ ok: false, error: answer.failure }, answer.failure === 'notConfigured' ? 503 : 502);
  }

  const review: ReviewPayload | null = normaliseReview(parseModelJson(answer.content));
  if (review === null) {
    console.error('ai-review: model returned an unusable payload');
    return json({ ok: false, error: 'malformed' }, 502);
  }

  // `user_id` comes from the verified JWT, not the body — the write can only ever attach the
  // review to the caller. `onConflict: user_id,trade_id` makes a re-request REPLACE the stored
  // review instead of appending a second one (migration 0007 adds that unique index).
  const { error: writeError } = await sb.from('ai_reviews').upsert(
    {
      user_id: userId,
      trade_id: tradeId,
      summary: review.summary,
      leak: review.leak,
      score: review.score,
      suggestions: review.suggestions,
      model: REVIEW_MODEL,
      prompt_version: PROMPT_VERSION,
    },
    { onConflict: 'user_id,trade_id' },
  );

  if (writeError) {
    console.error('ai-review: review write failed', writeError.code);
    return json({ ok: false, error: 'server' }, 500);
  }

  return json({
    ok: true,
    summary: review.summary,
    leak: review.leak,
    score: review.score,
    suggestions: review.suggestions,
    model: REVIEW_MODEL,
    prompt_version: PROMPT_VERSION,
  });
});
