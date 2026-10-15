// flutterwave-webhook — grants time-boxed `profiles.is_premium` on a Flutterwave
// charge.completed (or subscription.created).
//
//   POST /functions/v1/flutterwave-webhook  (called by Flutterwave, not the app)
//     body: the Flutterwave event JSON
//     header: verif-hash  (the secret hash configured in the Flutterwave dashboard)
//     -> 200 { ok: true, … }  on a verified charge.completed whose email matched a profile
//     -> 200 { ok: true, ignored: true } on any other event (ack so Flutterwave stops retrying)
//     -> 401 on a bad/missing signature, 405 on non-POST, 400 on a success with no email,
//        503 when FLUTTERWAVE_SECRET_KEY or the Supabase service config is missing, 500 on a
//        failed update.
//
// The grant is TIME-BOXED (migration 0013): the tier is inferred from
// `data.amount` (~$15 → 1 month, ~$40 → 3 months, ~$145 → 12 months,
// default 1 month) and the update sets BOTH `is_premium = true` AND
// `premium_expires_at`. The webhook never writes a NULL expiry — NULL is
// reserved for legacy/lifetime grants predating 0013.
//
// ── Authorization ───────────────────────────────────────────────────────────────
// This endpoint is called by Flutterwave's servers, NOT by the app, so it carries no Supabase
// JWT. `config.toml` therefore sets `verify_jwt = false` — the platform must not try to
// verify a JWT that will never be present. Authenticity is the `verif-hash` header,
// verified against `FLUTTERWAVE_SECRET_KEY` BEFORE the body is parsed.
//
// ── Secrets ──────────────────────────────────────────────────────────────────────
//   FLUTTERWAVE_SECRET_KEY     required — verifies the webhook signature. Lives only in
//                              `supabase secrets`, never in the app or any env/*.json.
//   SUPABASE_URL / SUPABASE_SERVICE_KEY  required — platform-provided. The service role is
//                              used to UPDATE `profiles.is_premium` +
//                              `premium_expires_at` (RLS is read-only for
//                              users, migrations 0012/0013), matched by email.
//
// ── Logging ──────────────────────────────────────────────────────────────────────
// Logs COUNTS and MASKED emails only (see `maskEmail` in ./shared.ts) — never the raw
// email, the request body, the signature, or the secret. The pure logic is unit-tested in
// `flutterwave_webhook_test.ts`; this file adds only the HTTP + Supabase I/O.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
  extractChargeAmount,
  extractCustomerEmail,
  inferTierMonths,
  isChargeSuccess,
  maskEmail,
  premiumExpiresAt,
  verifyWebhook,
} from './shared.ts';

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

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed' }, 405);

  const secret = Deno.env.get('FLUTTERWAVE_SECRET_KEY');
  if (!secret) {
    console.error('flutterwave-webhook: FLUTTERWAVE_SECRET_KEY is not set');
    return json({ ok: false, error: 'notConfigured' }, 503);
  }

  // Verify the `verif-hash` header against the secret hash BEFORE parsing or
  // trusting anything in the body.
  const rawBody = await req.text();
  const signature = req.headers.get('verif-hash');
  const valid = await verifyWebhook(rawBody, signature, secret);
  if (!valid) {
    // Log neither the body nor the signature — both can carry secrets/PII.
    console.error('flutterwave-webhook: signature verification failed');
    return json({ ok: false, error: 'Unauthorized' }, 401);
  }

  let payload: unknown;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return json({ ok: false, error: 'Bad request' }, 400);
  }

  // Acknowledge every event we do not act on, so Flutterwave stops retrying it.
  if (!isChargeSuccess(payload)) {
    return json({ ok: true, ignored: true }, 200);
  }

  const email = extractCustomerEmail(payload);
  if (!email) {
    console.error('flutterwave-webhook: success event carried no customer email');
    return json({ ok: false, error: 'Bad request' }, 400);
  }

  // deno-lint-ignore no-explicit-any
  let sb: any;
  try {
    sb = serviceClient();
  } catch (err) {
    console.error('flutterwave-webhook: service client unavailable', String(err));
    return json({ ok: false, error: 'notConfigured' }, 503);
  }

  try {
    // Service role bypasses RLS (the client policy is read-only, migration 0012), so this
    // is the only path that can set is_premium. Case-insensitive email match: Flutterwave
    // preserves whatever casing the trader typed at checkout, and profiles.email may be
    // stored differently.
    //
    // Time-boxed grant (migration 0013): the tier comes from `data.amount`
    // (~$15 → 1 month, ~$40 → 3 months, ~$145 → 12 months, unknown → 1 month)
    // and BOTH columns are written. `premium_expires_at` is always non-NULL
    // here — NULL remains the legacy/lifetime marker for pre-0013 grants.
    const months = inferTierMonths(extractChargeAmount(payload));
    const premiumExpiresAtIso = premiumExpiresAt(new Date(), months);
    const { error } = await sb
      .from('profiles')
      .update({ is_premium: true, premium_expires_at: premiumExpiresAtIso })
      .ilike('email', email)
      .select('id');

    if (error) {
      // Log the short code only — a PostgREST error body can echo column/table names.
      console.error('flutterwave-webhook: profiles update failed', error.code);
      return json({ ok: false, error: 'server' }, 500);
    }

    // Masked email + tier shape only — never the raw address or amount.
    console.log('flutterwave-webhook: premium granted to', maskEmail(email), `${months}m`);
    return json({ ok: true, months }, 200);
  } catch (err) {
    console.error('flutterwave-webhook: failed', String(err));
    return json({ ok: false, error: 'server' }, 500);
  }
});
