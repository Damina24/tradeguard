// Pure logic for the `flutterwave-webhook` Edge Function: signature verification,
// event filtering, customer-email extraction, tier/amount inference, expiry
// computation and email masking.
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
//   * **Grant is time-boxed, never lifetime.** The tier is inferred from
//     `data.amount` (migration 0013): ~$15 → 1 month, ~$40 → 3 months,
//     ~$145 → 12 months. An unrecognised amount defaults to 1 month — the
//     webhook NEVER writes a NULL `premium_expires_at` (NULL is reserved for
//     legacy/lifetime grants made before 0013).
//   * **Emails and secrets are never logged.** `maskEmail` keeps at most the
//     first character of the local part and domain; the raw address, the request
//     body and the signature header are never written to a log.

export const FLUTTERWAVE_EVENT_CHARGE_COMPLETED = 'charge.completed';
export const FLUTTERWAVE_EVENT_SUBSCRIPTION_CREATED = 'subscription.created';

/** Paywall tiers and their canonical USD prices (see `paywall_screen.dart`). */
export const TIER_MONTHLY_MONTHS = 1;
export const TIER_QUARTERLY_MONTHS = 3;
export const TIER_YEARLY_MONTHS = 12;
export const TIER_MONTHLY_AMOUNT = 14.99;
export const TIER_QUARTERLY_AMOUNT = 39.99;
export const TIER_YEARLY_AMOUNT = 144.99;

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
 * The charged amount in major currency units from a Flutterwave payload.
 *
 * Reads `data.amount` (falling back to `data.charged_amount`), coercing
 * numeric strings. Flutterwave sends NGN-style minor units on some rails, so a
 * value ≥ 1000 that is an exact multiple matching a tier price × 100 is
 * normalised (e.g. 1499 kobo → 14.99). Returns null when no usable amount is
 * present — the caller then falls back to the 1-month default rather than
 * writing a lifetime grant.
 */
export function extractChargeAmount(payload: unknown): number | null {
  if (typeof payload !== 'object' || payload === null) return null;
  const root = payload as Record<string, unknown>;
  const data = root.data;
  if (typeof data !== 'object' || data === null) return null;
  const d = data as Record<string, unknown>;
  const raw = d.amount ?? d.charged_amount;
  const num = typeof raw === 'number' ? raw : typeof raw === 'string' && raw.trim() !== '' ? Number(raw) : NaN;
  if (!Number.isFinite(num) || num <= 0) return null;
  // Minor-unit normalisation: 1499 → 14.99, 3999 → 39.99, 14499 → 144.99.
  const tiers = [TIER_MONTHLY_AMOUNT, TIER_QUARTERLY_AMOUNT, TIER_YEARLY_AMOUNT];
  for (const tier of tiers) {
    if (Math.abs(num - tier * 100) < 0.5) return tier;
  }
  return num;
}

/**
 * Subscription length in months inferred from the charged amount.
 *
 * ±$0.50 tolerance around each tier price absorbs FX rounding and gateway
 * fees: ~$15 → 1 month, ~$40 → 3 months, ~$145 → 12 months. Anything else
 * defaults to 1 month (fail-closed: under-grant, never over-grant).
 */
export function inferTierMonths(amount: number | null): number {
  if (amount === null || !Number.isFinite(amount)) return TIER_MONTHLY_MONTHS;
  if (Math.abs(amount - TIER_YEARLY_AMOUNT) <= 0.5) return TIER_YEARLY_MONTHS;
  if (Math.abs(amount - TIER_QUARTERLY_AMOUNT) <= 0.5) return TIER_QUARTERLY_MONTHS;
  return TIER_MONTHLY_MONTHS;
}

/** `premium_expires_at` for a grant starting at `from` lasting `months`. */
export function premiumExpiresAt(from: Date, months: number): string {
  const d = new Date(from.getTime());
  d.setUTCMonth(d.getUTCMonth() + months);
  return d.toISOString();
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
