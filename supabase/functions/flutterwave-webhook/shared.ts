// Pure logic for the `flutterwave-webhook` Edge Function: signature verification,
// event filtering, customer-email extraction and email masking.
//
// Split out of `index.ts` for the same reason as `copy-signal/shared.ts` — this
// module touches neither `Deno.env` nor the network, so `flutterwave_webhook_test.ts`
// verifies every rule in CI (Node 22+ or `deno test`) without a runtime and
// without a Supabase project. `index.ts` imports from here and adds only I/O.
//
// ── Contract ──────────────────────────────────────────────────────────────────
//   Flutterwave POSTs a JSON body and sends the secret hash in the `verif-hash`
//   header. We compare that header against FLUTTERWAVE_SECRET_KEY in constant
//   time BEFORE parsing or trusting anything in the body.
//
// ── Security contract ─────────────────────────────────────────────────────────
//   * **Signature first, always.** The `verif-hash` header is verified before
//     the body is parsed or trusted.
//   * **Only `charge.completed` / `subscription.created` grant premium.** Every
//     other event is acknowledged with 200 so Flutterwave stops retrying it,
//     but changes nothing.
//   * **Emails and secrets are never logged.** `maskEmail` keeps at most the
//     first character of the local part and domain; the raw address, the request
//     body and the signature header are never written to a log.

export const FLUTTERWAVE_EVENT_CHARGE_COMPLETED = 'charge.completed';
export const FLUTTERWAVE_EVENT_SUBSCRIPTION_CREATED = 'subscription.created';

/** True when the payload's `event` grants premium (`charge.completed`). */
export function isChargeSuccess(payload: unknown): boolean {
  if (typeof payload !== 'object' || payload === null) return false;
  const event = (payload as Record<string, unknown>).event;
  return (
    event === FLUTTERWAVE_EVENT_CHARGE_COMPLETED ||
    event === FLUTTERWAVE_EVENT_SUBSCRIPTION_CREATED
  );
}

/**
 * The customer email from a Flutterwave payload.
 * Supports `data.customer.email`, `data.customer_email` and top-level
 * `customer.email` shapes, or null.
 */
export function extractCustomerEmail(payload: unknown): string | null {
  if (typeof payload !== 'object' || payload === null) return null;
  const root = payload as Record<string, unknown>;
  const candidates: unknown[] = [];
  const data = root.data;
  if (typeof data === 'object' && data !== null) {
    const d = data as Record<string, unknown>;
    const customer = d.customer;
    if (typeof customer === 'object' && customer !== null) {
      candidates.push((customer as Record<string, unknown>).email);
    }
    candidates.push(d.customer_email);
    candidates.push(d.email);
  }
  const customer = root.customer;
  if (typeof customer === 'object' && customer !== null) {
    candidates.push((customer as Record<string, unknown>).email);
  }
  for (const candidate of candidates) {
    if (typeof candidate === 'string' && candidate.includes('@')) {
      return candidate;
    }
  }
  return null;
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

/** Flutterwave's `verif-hash` scheme: the header carries the secret hash. */
export async function computeSignature(
  _rawBody: string,
  secret: string,
): Promise<string> {
  return secret;
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
