// paystack-webhook — flips `profiles.is_premium` to true on a Paystack charge.success.
//
//   POST /functions/v1/paystack-webhook        (called by Paystack, not the app)
//     body: the Paystack event JSON
//     header: x-paystack-signature  (HMAC-SHA512 of the raw body, keyed by the secret key)
//     -> 200 { ok: true }  on a verified charge.success whose email matched a profile
//     -> 200 { ok: true, ignored: true } on any other event (ack so Paystack stops retrying)
//     -> 401 on a bad/missing signature, 405 on non-POST, 400 on a success with no email,
//        503 when PAYSTACK_SECRET_KEY or the Supabase service config is missing, 500 on a
//        failed update.
//
// ── Authorization ───────────────────────────────────────────────────────────────
// This endpoint is called by Paystack's servers, NOT by the app, so it carries no Supabase
// JWT. `config.toml` therefore sets `verify_jwt = false` — the platform must not try to
// verify a JWT that will never be present. Authenticity is the HMAC-SHA512 signature in
// `x-paystack-signature`, verified against `PAYSTACK_SECRET_KEY` BEFORE the body is parsed.
//
// ── Secrets ──────────────────────────────────────────────────────────────────────
//   PAYSTACK_SECRET_KEY        required — verifies the webhook signature. Lives only in
//                              `supabase secrets`, never in the app or any env/*.json.
//   SUPABASE_URL / SUPABASE_SERVICE_KEY  required — platform-provided. The service role is
//                              used to UPDATE `profiles.is_premium` (RLS is read-only for
//                              users, migration 0012), matched by the customer's email.
//
// ── Logging ──────────────────────────────────────────────────────────────────────
// Logs COUNTS and MASKED emails only (see `maskEmail` in ./shared.ts) — never the raw
// email, the request body, the signature, or the secret. The pure logic is unit-tested in
// `paystack_webhook_test.ts`; this file adds only the HTTP + Supabase I/O.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
  extractCustomerEmail,
  isChargeSuccess,
  maskEmail,
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

  const secret = Deno.env.get('PAYSTACK_SECRET_KEY');
  if (!secret) {
    console.error('paystack-webhook: PAYSTACK_SECRET_KEY is not set');
    return json({ ok: false, error: 'notConfigured' }, 503);
  }

  // Read the RAW body first: the signature is over the exact bytes, so it must be
  // verified before the body is parsed. A re-serialized body would not match.
  const rawBody = await req.text();
  const signature = req.headers.get('x-paystack-signature');
  const valid = await verifyWebhook(rawBody, signature, secret);
  if (!valid) {
    // Log neither the body nor the signature — both can carry secrets/PII.
    console.error('paystack-webhook: signature verification failed');
    return json({ ok: false, error: 'Unauthorized' }, 401);
  }

  let payload: unknown;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return json({ ok: false, error: 'Bad request' }, 400);
  }

  // Acknowledge every event we do not act on, so Paystack stops retrying it.
  if (!isChargeSuccess(payload)) {
    return json({ ok: true, ignored: true }, 200);
  }

  const email = extractCustomerEmail(payload);
  if (!email) {
    console.error('paystack-webhook: charge.success carried no customer email');
    return json({ ok: false, error: 'Bad request' }, 400);
  }

  // deno-lint-ignore no-explicit-any
  let sb: any;
  try {
    sb = serviceClient();
  } catch (err) {
    console.error('paystack-webhook: service client unavailable', String(err));
    return json({ ok: false, error: 'notConfigured' }, 503);
  }

  try {
    // Service role bypasses RLS (the client policy is read-only, migration 0012), so this
    // is the only path that can set is_premium. Case-insensitive email match: Paystack
    // preserves whatever casing the trader typed at checkout, and profiles.email may be
    // stored differently.
    const { error } = await sb
      .from('profiles')
      .update({ is_premium: true })
      .ilike('email', email)
      .select('id');

    if (error) {
      // Log the short code only — a PostgREST error body can echo column/table names.
      console.error('paystack-webhook: profiles update failed', error.code);
      return json({ ok: false, error: 'server' }, 500);
    }

    // Masked email + a success flag only.
    console.log('paystack-webhook: premium granted to', maskEmail(email));
    return json({ ok: true }, 200);
  } catch (err) {
    console.error('paystack-webhook: failed', String(err));
    return json({ ok: false, error: 'server' }, 500);
  }
});
