// Tests for `flutterwave-webhook`. Mirrors the `delete_account_test.ts` harness: a tiny
// `test`/`eq`/`ok` runner, no framework, no runtime, no Supabase project. It drives the
// pure logic in `shared.ts` so the contract Flutterwave and the store reviewers care about is
// verified in CI:
//   * signature verification — the `verif-hash` header must equal the secret hash;
//     a wrong hash / missing header / empty secret fails;
//   * event filtering — only `charge.completed` / `subscription.created` are acted on;
//     every other event is ignored;
//   * email extraction — the customer email is read from the Flutterwave payload
//     and a payload with no email yields null;
//   * tier inference (migration 0013) — `data.amount` maps to months
//     (~$15 → 1, ~$40 → 3, ~$145 → 12, unknown → 1) and the expiry helper
//     advances whole calendar months;
//   * masking — `maskEmail` never leaks the full local part or domain.
//
// Run with:  node supabase/functions/flutterwave-webhook/flutterwave_webhook_test.ts
// (Node 22+ strips the types natively; `crypto.subtle` is global in Node 18+. `deno test`
// works too.)

import {
  extractChargeAmount,
  extractCustomerEmail,
  inferTierMonths,
  isChargeSuccess,
  maskEmail,
  premiumExpiresAt,
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

const SECRET = 'FLUTWSECK_TEST-abcdef0123456789';
const PAYLOAD = {
  event: 'charge.completed',
  data: { customer: { email: 'john.doe@example.com' } },
};
// The Flutterwave `verif-hash` header carries the secret hash itself.
const BODY = JSON.stringify(PAYLOAD);

// ---------------------------------------------------------------------------------------------
// Signature verification
// ---------------------------------------------------------------------------------------------

test('a matching verif-hash verifies', async () => {
  eq(await verifyWebhook(BODY, SECRET, SECRET), true);
});

test('a wrong verif-hash is rejected', async () => {
  eq(await verifyWebhook(BODY, 'wrong-hash', SECRET), false);
});

test('a missing header signature is rejected', async () => {
  eq(await verifyWebhook(BODY, null, SECRET), false);
});

test('an empty secret is rejected', async () => {
  eq(await verifyWebhook(BODY, SECRET, ''), false);
});

test('signaturesMatch rejects a different-length digest', () => {
  eq(signaturesMatch('abc', 'abcd'), false);
  eq(signaturesMatch('abc', 'abc'), true);
  eq(signaturesMatch('abc', 'abd'), false);
});

// ---------------------------------------------------------------------------------------------
// Event filtering
// ---------------------------------------------------------------------------------------------

test('only charge.completed / subscription.created are acted on', () => {
  eq(isChargeSuccess({ event: 'charge.completed' }), true);
  eq(isChargeSuccess({ event: 'subscription.created' }), true);
  eq(isChargeSuccess({ event: 'charge.success' }), false);
  eq(isChargeSuccess({ event: 'transfer.completed' }), false);
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
  eq(extractCustomerEmail({ event: 'charge.completed', data: {} }), null);
  eq(extractCustomerEmail({ event: 'charge.completed' }), null);
  eq(
    extractCustomerEmail({
      event: 'charge.completed',
      data: { customer: {} },
    }),
    null,
  );
  eq(
    extractCustomerEmail({
      event: 'charge.completed',
      data: { customer: { email: 42 } },
    }),
    null,
  );
  eq(extractCustomerEmail(null), null);
});

// ---------------------------------------------------------------------------------------------
// Tier inference + expiry (migration 0013: no more lifetime grants)
// ---------------------------------------------------------------------------------------------

test('amounts map to their tier months', () => {
  eq(inferTierMonths(extractChargeAmount({ data: { amount: 14.99 } })), 1);
  eq(inferTierMonths(extractChargeAmount({ data: { amount: 39.99 } })), 3);
  eq(inferTierMonths(extractChargeAmount({ data: { amount: 144.99 } })), 12);
});

test('amount inference tolerates FX rounding and string/minor-unit shapes', () => {
  eq(inferTierMonths(extractChargeAmount({ data: { amount: 15.2 } })), 1);
  eq(inferTierMonths(extractChargeAmount({ data: { amount: '39.99' } })), 3);
  eq(inferTierMonths(extractChargeAmount({ data: { amount: 14499 } })), 12);
  eq(inferTierMonths(extractChargeAmount({ data: { charged_amount: 1499 } })), 1);
});

test('unknown or missing amounts fail closed to 1 month, never lifetime', () => {
  eq(inferTierMonths(extractChargeAmount({ data: { amount: 999 } })), 1);
  eq(inferTierMonths(extractChargeAmount({ data: {} })), 1);
  eq(inferTierMonths(extractChargeAmount({})), 1);
  eq(inferTierMonths(extractChargeAmount(null)), 1);
  eq(inferTierMonths(null), 1);
});

test('premiumExpiresAt advances whole calendar months in UTC', () => {
  const from = new Date('2026-01-15T00:00:00.000Z');
  eq(premiumExpiresAt(from, 1), '2026-02-15T00:00:00.000Z');
  eq(premiumExpiresAt(from, 3), '2026-04-15T00:00:00.000Z');
  eq(premiumExpiresAt(from, 12), '2027-01-15T00:00:00.000Z');
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
  console.log(`flutterwave-webhook: ${passed} tests passed`);
}

await main();
