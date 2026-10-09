// delete-account — in-app account deletion for store compliance (Apple 5.1.1(v), Google Play
// account-deletion policy).
//
//   POST /functions/v1/delete-account   (no body)
//     -> { ok: true, deleted: {<table>: n, ...}, storage: n, user_deleted: true }
//
// The caller's own account and every row they own are removed, then the auth user. It is idempotent:
// a second call finds nothing left and still returns a success summary. The deletion ORDER and the
// table LIST live in `./shared.ts` (enumerated from migrations 0001–0010, child-first) and are
// unit-tested there without a runtime; this file adds only the GoTrue auth + service-role wiring.
//
// ── Authorization ───────────────────────────────────────────────────────────────────────────────
// The same user-facing shape as `copy-signal` / `ai-review`, NOT the cron shape:
//   * `verify_jwt = true` (config.toml) rejects anonymous calls at the platform.
//   * The caller is resolved with GoTrue from their OWN bearer token; the uid is NEVER read from a
//     body (there is no body) and never from a header other than the verified JWT.
//   * Every delete the service role performs is scoped to that verified uid, so the endpoint can
//     only ever remove the caller's own data.
//
// ── Logging ────────────────────────────────────────────────────────────────────────────────────
// Logs COUNTS and short CODES only — never a request/response body, never a uid, never a row. A
// PostgREST error body can echo table and column names; none of that is worth persisting.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
  classifyStatus,
  DeleteError,
  parseBearer,
  runDelete,
} from './shared.ts';
import type { DeleteClient } from './shared.ts';

// deno-lint-ignore no-explicit-any
function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

// deno-lint-ignore no-explicit-any
function serviceClient(): any {
  const key = Deno.env.get('SUPABASE_SERVICE_KEY');
  const url = Deno.env.get('SUPABASE_URL');
  if (!key || !url) {
    throw new Error('SUPABASE_SERVICE_KEY / SUPABASE_URL is not set');
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** The caller's user id, resolved from their own bearer token (same contract as `copy-signal`). */
async function callerId(authHeader: string | null): Promise<string | null> {
  if (parseBearer(authHeader) === null) return null;
  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!url || !anonKey) return null;

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader as string } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await userClient.auth.getUser();
  if (error) return null;
  const id = data?.user?.id;
  return typeof id === 'string' && id.length > 0 ? id : null;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed' }, 405);

  const userId = await callerId(req.headers.get('Authorization'));
  if (userId === null) return json({ ok: false, error: 'Unauthorized' }, 401);

  // deno-lint-ignore no-explicit-any
  let sb: any;
  try {
    sb = serviceClient();
  } catch (err) {
    console.error('delete-account: service client unavailable', String(err));
    return json({ ok: false, error: 'notConfigured' }, 503);
  }

  try {
    const summary = await runDelete(sb as DeleteClient, userId);
    // Counts only — the table names are already known from source and the numbers carry no PII.
    console.log(
      'delete-account: ok rows=',
      JSON.stringify(summary.deleted),
      'storage=',
      summary.storage,
    );
    return json(summary, 200);
  } catch (err) {
    // Log the short code (a table name or 'deleteUser'/'storage'), never a body.
    const code = err instanceof DeleteError ? err.code : 'unknown';
    console.error('delete-account: failed', code);
    return json({ ok: false, error: classifyStatus(500) }, 500);
  }
});
