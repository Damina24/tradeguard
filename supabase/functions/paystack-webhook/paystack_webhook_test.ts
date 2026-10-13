// Tests for `paystack-webhook`. Mirrors the `delete_account_test.ts` harness: a tiny
// `test`/`eq`/`ok` runner, no framework, no runtime, no Supabase project. It drives the
// pure logic in `shared.ts` so the contract Paystack and the store reviewers care about is
// verified in CI:
//   * signature verification — a correct HMAC-SHA512 passes, a wrong secret / wrong body /
//     missing header fails, and a digest of different length is rejected;
//   * event filtering — only `charge.success` is acted on; every other event is ignored;
//   * email extraction — the customer email is read from data.customer.email and a payload
//     with no email yields null;
//   * masking — `maskEmail` never leaks the full local part or domain.
//
// Run with:  node supabase/functions/paystack-webhook/paystack_webhook_test.ts
// (Node 22+ strips the types natively; `crypto.subtle` is global in Node 18+. `deno test`
// works too.)

import {
  computeSignature,
  extractCustomerEmail,
  isChargeSuccess,
  maskEmail,
  signaturesMatch,
  verifyWebhook,
} from './shared.ts';

const tests: Array<{ name: string; fn: () => void | Promise<void> }> = [];
function test(name: string, fn: () => void | Promise<void>): void {
  tests.push({ name, fn });
}

function eq(actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`expected ${e}, got ${a}`);
}

function ok(value: boolean, note = ''): void {
  if (!value) throw new Error(`expected truthy ${note}`);
}

const SECRET = 'sk_test_abcdef0123456789';
const PAYLOAD = {
  event: 'charge.success',
  data: { customer: { email: 'john.doe@example.com' } },
};
// The raw body is what Paystack signs, so it is kept as a string for the signature tests.
const BODY = JSON.stringify(PAYLOAD);

// ---------------------------------------------------------------------------------------------
// Signature verification
// ---------------------------------------------------------------------------------------------

test('a correct HMAC-SHA512 signature verifies', async () => {
  const sig = await computeSignature(BODY, SECRET);
  ok(sig.length === 128, `sha512 hex should be 128 chars, got ${sig.length}`);
  eq(await verifyWebhook(BODY, sig, SECRET), true);
});

test('a signature from the wrong secret is rejected', async () => {
  const sig = await computeSignature(BODY, 'sk_wrong_secret');
  eq(await verifyWebhook(BODY, sig, SECRET), false);
});

test('a signature over a different body is rejected', async () => {
  const sig = await computeSignature(BODY, SECRET);
  const other = JSON.stringify({
    event: 'charge.success',
    data: { customer: { email: 'attacker@evil.com' } },
  });
  eq(await verifyWebhook(other, sig, SECRET), false);
});

test('a missing header signature is rejected', async () => {
  eq(await verifyWebhook(BODY, null, SECRET), false);
});

test('an empty secret is rejected', async () => {
  const sig = await computeSignature(BODY, SECRET);
  eq(await verifyWebhook(BODY, sig, ''), false);
});

test('signaturesMatch rejects a different-length digest', () => {
  eq(signaturesMatch('abc', 'abcd'), false);
  eq(signaturesMatch('abc', 'abc'), true);
  eq(signaturesMatch('abc', 'abd'), false);
});

// ---------------------------------------------------------------------------------------------
// Event filtering
// ---------------------------------------------------------------------------------------------

test('only charge.success is acted on', () => {
  eq(isChargeSuccess({ event: 'charge.success' }), true);
  eq(isChargeSuccess({ event: 'subscription.create' }), false);
  eq(isChargeSuccess({ event: 'transfer.success' }), false);
  eq(isChargeSuccess({}), false);
  eq(isChargeSuccess(null), false);
});

// ---------------------------------------------------------------------------------------------
// Email extraction
// ---------------------------------------------------------------------------------------------

test('the customer email is read from data.customer.email', () => {
  eq(extractCustomerEmail(PAYLOAD), 'john.doe@example.com');
});

test('a payload with no customer email yields null', () => {
  eq(extractCustomerEmail({ event: 'charge.success', data: {} }), null);
  eq(extractCustomerEmail({ event: 'charge.success' }), null);
  eq(extractCustomerEmail({ event: 'charge.success', data: { customer: {} } }), null);
  eq(extractCustomerEmail({ event: 'charge.success', data: { customer: { email: 42 } } }), null);
  eq(extractCustomerEmail(null), null);
});

// ---------------------------------------------------------------------------------------------
// Masking
// ---------------------------------------------------------------------------------------------

test('maskEmail hides the local part and domain but keeps the shape', () => {
  const masked = maskEmail('john.doe@example.com');
  eq(masked, 'j***@e***.com');
  ok(!masked.includes('john'), 'must not contain the local part');
  ok(!masked.includes('example'), 'must not contain the domain name');
});

test('maskEmail collapses a malformed value', () => {
  eq(maskEmail('no-at-sign'), '***');
});

// ---------------------------------------------------------------------------------------------

async function main(): Promise<void> {
  let passed = 0;
  const failures: string[] = [];
  for (const { name, fn } of tests) {
    try {
      await fn();
      passed++;
    } catch (err) {
      failures.push(`${name}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }
  if (failures.length > 0) {
    console.error(
      `\n${failures.length} failing:\n` + failures.map((f) => `  - ${f}`).join('\n'),
    );
    throw new Error(`${passed} passed, ${failures.length} failed`);
  }
  console.log(`paystack-webhook: ${passed} tests passed`);
}

await main();
