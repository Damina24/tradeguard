// Pure logic for the `paystack-webhook` Edge Function: signature verification,
// event filtering, customer-email extraction and email masking.
//
// Split out of `index.ts` for the same reason as `copy-signal/shared.ts` — this
// module touches neither `Deno.env` nor the network, so `paystack_webhook_test.ts`
// verifies every rule in CI (Node 22+ or `deno test`) without a runtime and
// without a Supabase project. `index.ts` imports from here and adds only I/O.
//
// ── Contract ──────────────────────────────────────────────────────────────────
//   Paystack POSTs a JSON body and signs the RAW bytes with HMAC-SHA512 keyed by
//   the secret key, sending the hex digest in the `x-paystack-signature` header.
//   We recompute that digest over the exact bytes we received and compare it in
//   constant time BEFORE parsing or trusting anything in the body.
//
// ── Security contract ─────────────────────────────────────────────────────────
//   * **Signature first, always.** The body is read as raw text and verified
//     before it is parsed; a re-serialized body would not match the signature.
//   * **Only `charge.success` grants premium.** Every other event is acknowledged
//     with 200 so Paystack stops retrying it, but changes nothing.
//   * **Emails and secrets are never logged.** `maskEmail` keeps at most the
//     first character of the local part and domain; the raw address, the request
//     body and the signature header are never written to a log.

export const PAYSTACK_EVENT_CHARGE_SUCCESS = 'charge.success';

/** True when the payload's `event` is exactly `charge.success`. */
export function isChargeSuccess(payload: unknown): boolean {
  if (typeof payload !== 'object' || payload === null) return false;
  return (payload as Record<string, unknown>).event === PAYSTACK_EVENT_CHARGE_SUCCESS;
}

/** The customer email from a Paystack payload (`data.customer.email`), or null. */
export function extractCustomerEmail(payload: unknown): string | null {
  if (typeof payload !== 'object' || payload === null) return null;
  const data = (payload as Record<string, unknown>).data;
  if (typeof data !== 'object' || data === null) return null;
  const customer = (data as Record<string, unknown>).customer;
  if (typeof customer !== 'object' || customer === null) return null;
  const email = (customer as Record<string, unknown>).email;
  return typeof email === 'string' && email.includes('@') ? email : null;
}

/**
 * Masks an email for logging: keeps the first character of the local part and
 * of the domain and the TLD, e.g. `john.doe@example.com` -> `j***@e***.com`.
 * A malformed value (no `@`) collapses to `***`.
 */
export function maskEmail(email: string): string {
  const at = email.indexOf('@');
  if (at <= 0) return '***';
  const local = email.slice(0, at);
  const domain = email.slice(at + 1);
  const dot = domain.lastIndexOf('.');
  const domainHead = dot > 0 ? domain.slice(0, dot) : domain;
  const tld = dot > 0 ? domain.slice(dot) : '';
  const l = local.length > 0 ? local[0] : '';
  const d = domainHead.length > 0 ? domainHead[0] : '';
  return `${l}***@${d}***${tld}`;
}

/** HMAC-SHA512 of `rawBody` keyed by `secret`, hex-encoded (Paystack's scheme). */
export async function computeSignature(rawBody: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-512' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
  return Array.from(new Uint8Array(mac))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/** Length-safe, timing-independent string equality for hex digests. */
export function signaturesMatch(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

/** True only when a non-empty secret and header produce a matching signature. */
export async function verifyWebhook(
  rawBody: string,
  headerSignature: string | null,
  secret: string,
): Promise<boolean> {
  if (!secret || !headerSignature) return false;
  const expected = await computeSignature(rawBody, secret);
  return signaturesMatch(expected, headerSignature);
}
