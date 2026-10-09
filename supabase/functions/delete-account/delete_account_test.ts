// Tests for `delete-account`. Mirrors the `copy_signal_test.ts` harness: a tiny `test`/`eq`/`ok`
// runner, no framework, no runtime, no Supabase project. It drives the pure orchestration in
// `shared.ts` against a FAKE client that records every call, so the contract the store reviewers
// care about is verified in CI:
//   * auth required — a missing/malformed bearer resolves to no caller (the handler answers 401);
//   * rows deleted — every user-owned table is deleted, scoped to the caller's uid, child-first;
//   * storage prefix deleted — objects under the uid are listed and removed;
//   * idempotent second call — a second run finds nothing and still returns a success summary, and
//     an already-deleted user from `deleteUser` is treated as success, not an error.
//
// The Dart suite (`test/delete_account_*_test.dart`) tests the client half of the same contract —
// the confirm gating, the sign-out on success, and the trader-safe error copy.
//
// Run with:  node supabase/functions/delete-account/delete_account_test.ts
// (Node 22+ strips the types natively. `deno test` works too.)

import {
  classifyStatus,
  DeleteError,
  deleteAccountData,
  isUserGone,
  parseBearer,
  runDelete,
  SCREENSHOTS_BUCKET,
  TABLES,
} from './shared.ts';
import type { DeleteClient } from './shared.ts';

// Async-aware runner: every test may return a promise, and all are awaited before the verdict.
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

const UID = '11111111-2222-3333-4444-555555555555';

/** One recorded table delete. */
interface DeleteCall {
  table: string;
  column: string;
  value: string;
}

/**
 * A recording fake of [DeleteClient]. Every call is captured so the test can assert the table list,
 * the child-first order, the uid scoping, the storage prefix and idempotency — with no network.
 *
 * `rowCounts` seeds how many rows each table "had"; `objects` seeds the storage tree as full paths
 * (`<uid>/<trade-id>/<file>`); `userGone` makes `deleteUser` report the user as already removed;
 * `failTable` makes that table's delete return an error.
 */
function fakeClient(opts: {
  rowCounts?: Record<string, number>;
  objects?: string[];
  userGone?: boolean;
  failTable?: string;
} = {}): { client: DeleteClient; deletes: DeleteCall[]; removed: string[]; listed: string[] } {
  const rowCounts = opts.rowCounts ?? {};
  const deletes: DeleteCall[] = [];
  const removed: string[] = [];
  const listed: string[] = [];

  // Model the storage tree as a mutable set of full paths so `remove` actually empties it and a
  // second call lists nothing — the real idempotency path.
  const tree = new Set<string>(opts.objects ?? []);

  const client: DeleteClient = {
    from(table: string) {
      return {
        delete() {
          return {
            eq(column: string, value: string) {
              deletes.push({ table, column, value });
              if (opts.failTable === table) {
                return Promise.resolve({ count: 0, error: { message: 'boom' } });
              }
              return Promise.resolve({ count: rowCounts[table] ?? 0, error: null });
            },
          };
        },
      };
    },
    storage: {
      from(bucket: string) {
        return {
          list(path: string) {
            listed.push(`${bucket}:${path}`);
            // Immediate children of `path`: folders (still have descendants) and files (leaf).
            const prefix = `${path}/`;
            const names = new Set<string>();
            for (const full of tree) {
              if (!full.startsWith(prefix)) continue;
              const rest = full.slice(prefix.length);
              names.add(rest.split('/')[0]);
            }
            const data = [...names].map((name) => {
              const child = `${path}/${name}`;
              const isFolder = [...tree].some((f) => f.startsWith(`${child}/`));
              return { name, id: isFolder ? null : 'obj-1' };
            });
            return Promise.resolve({ data, error: null });
          },
          remove(paths: string[]) {
            removed.push(...paths);
            for (const p of paths) tree.delete(p);
            return Promise.resolve({ error: null });
          },
        };
      },
    },
    auth: {
      admin: {
        deleteUser() {
          return Promise.resolve({ error: opts.userGone ? { status: 404 } : null });
        },
      },
    },
  };

  return { client, deletes, removed, listed };
}

// ---------------------------------------------------------------------------------------------
// Auth gate (the handler turns a null caller into 401)
// ---------------------------------------------------------------------------------------------

test('a missing bearer resolves to no caller', () => {
  eq(parseBearer(null), null);
});

test('a non-bearer authorization header resolves to no caller', () => {
  eq(parseBearer('Basic abc123'), null);
  eq(parseBearer(''), null);
});

test('a well-formed bearer token is returned', () => {
  eq(parseBearer('Bearer token-abc'), 'token-abc');
});

// ---------------------------------------------------------------------------------------------
// Rows deleted — every user-owned table, scoped to the uid, child-first
// ---------------------------------------------------------------------------------------------

test('deletes every user-owned table, scoped to the caller uid', async () => {
  const { client, deletes } = fakeClient({ rowCounts: { trades: 3, profiles: 1 } });
  const summary = await runDelete(client, UID);
  eq(deletes.length, TABLES.length);
  for (const call of deletes) {
    eq(call.value, UID); // every statement is scoped to the caller
  }
  eq(summary.deleted.trades, 3);
  eq(summary.deleted.profiles, 1);
  eq(summary.user_deleted, true);
});

test('profiles is scoped by id (its primary key), not user_id', async () => {
  const { client, deletes } = fakeClient();
  await runDelete(client, UID);
  const profile = deletes.find((d) => d.table === 'profiles');
  ok(profile !== undefined, 'profiles delete missing');
  eq(profile!.column, 'id');
});

test('children are deleted before their parent (child-first order)', async () => {
  const { client, deletes } = fakeClient();
  await runDelete(client, UID);
  const order = deletes.map((d) => d.table);
  // ai_reviews references trades; trades & signal_follows reference broker_accounts; broker_accounts
  // and copy_settings reference profiles. Each child must precede its parent.
  ok(order.indexOf('ai_reviews') < order.indexOf('trades'));
  ok(order.indexOf('trades') < order.indexOf('broker_accounts'));
  ok(order.indexOf('signal_follows') < order.indexOf('broker_accounts'));
  ok(order.indexOf('broker_accounts') < order.indexOf('profiles'));
  ok(order.indexOf('copy_settings') < order.indexOf('profiles'));
});

test('global tables are never touched', async () => {
  const { client, deletes } = fakeClient();
  await runDelete(client, UID);
  const tables = new Set(deletes.map((d) => d.table));
  ok(!tables.has('signals'), 'signals must not be deleted');
  ok(!tables.has('prices_cache'), 'prices_cache must not be deleted');
  ok(!tables.has('equity_snapshots'), 'equity_snapshots cascades via broker_accounts');
});

// ---------------------------------------------------------------------------------------------
// Storage prefix deleted
// ---------------------------------------------------------------------------------------------

test('storage objects under the uid prefix are listed and removed', async () => {
  const { client, removed, listed } = fakeClient({
    objects: [`${UID}/t1/1.jpg`, `${UID}/t1/2.png`, `${UID}/t2/3.webp`],
  });
  const summary = await runDelete(client, UID);
  eq(listed[0], `${SCREENSHOTS_BUCKET}:${UID}`); // first listing is the uid prefix
  eq(summary.storage, 3);
  eq(removed.length, 3);
  for (const path of removed) {
    ok(path.startsWith(`${UID}/`), `path outside uid prefix: ${path}`);
  }
});

test('an empty storage prefix removes nothing and reports zero', async () => {
  const { client, removed } = fakeClient({ objects: [] });
  const summary = await runDelete(client, UID);
  eq(summary.storage, 0);
  eq(removed.length, 0);
});


// ---------------------------------------------------------------------------------------------
// Idempotent second call
// ---------------------------------------------------------------------------------------------

test('a second call finds nothing left and still succeeds', async () => {
  const f = fakeClient({ rowCounts: { trades: 2, profiles: 1 }, objects: [`${UID}/t1/1.jpg`] });

  const first = await runDelete(f.client, UID);
  eq(first.ok, true);
  eq(first.deleted.trades, 2);
  eq(first.storage, 1);

  const second = await runDelete(f.client, UID);
  eq(second.ok, true);
  eq(second.user_deleted, true);
  // The row counts the fake returns are seeded, but the storage tree was actually emptied.
  eq(second.storage, 0);
});

test('an already-deleted user from deleteUser is treated as success', async () => {
  const { client } = fakeClient({ userGone: true });
  const summary = await runDelete(client, UID);
  eq(summary.ok, true);
  eq(summary.user_deleted, true);
});

test('isUserGone recognises a 404 and rejects a real error', () => {
  eq(isUserGone({ status: 404 }), true);
  eq(isUserGone({ code: 'user_not_found' }), true);
  eq(isUserGone({ status: 500 }), false);
  eq(isUserGone(null), false);
});

// ---------------------------------------------------------------------------------------------
// Error surfacing — codes only, never bodies
// ---------------------------------------------------------------------------------------------

test('a failing table delete throws a DeleteError carrying only the table name', async () => {
  const { client } = fakeClient({ failTable: 'trades' });
  let caught: unknown;
  try {
    await deleteAccountData(client, UID);
  } catch (err) {
    caught = err;
  }
  ok(caught instanceof DeleteError, 'expected DeleteError');
  eq((caught as DeleteError).code, 'trades');
});

test('classifyStatus maps statuses onto safe tokens', () => {
  eq(classifyStatus(401), 'Unauthorized');
  eq(classifyStatus(405), 'Method not allowed');
  eq(classifyStatus(503), 'notConfigured');
  eq(classifyStatus(500), 'server');
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
  console.log(`delete-account: ${passed} tests passed`);
}

await main();

