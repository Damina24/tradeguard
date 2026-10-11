// Pure orchestration for the `delete-account` Edge Function (Apple 5.1.1(v) / Google Play
// account-deletion). Split out of `index.ts` for the same reason as `copy-signal/shared.ts`: this
// module touches neither `Deno.env` nor the network, so `delete_account_test.ts` verifies the
// whole deletion contract in CI under plain `node` with a fake client — no runtime, no project.
// `index.ts` imports from here and adds only the GoTrue auth + service-role wiring.
//
// ── Contract ─────────────────────────────────────────────────────────────────────────────────────
//   POST /functions/v1/delete-account   (no body)
//     -> { ok: true, deleted: {<table>: n, ...}, storage: n, user_deleted: true }
//
// ── Deletion target list ─────────────────────────────────────────────────────────────────────────
// Enumerated by reading migrations 0001–0011 for EVERY table with a `user_id` column, then ordered
// child-first so an explicit delete never races a parent's ON DELETE CASCADE. This is the single
// source of truth for both the function and its test — do not special-case it elsewhere.
//   * ai_reviews, signal_follows, trade_sync_cursors, trades  — reference another user table, so
//     they are removed before that parent.
//   * broker_accounts — its delete CASCADEs `equity_snapshots` (which has NO `user_id`; it is owned
//     transitively through `broker_accounts.account_id`), so no separate statement is needed.
//   * copy_settings, api_rate_limits — reference `profiles` only.
//   * profiles — keyed by `id` (the uid), not `user_id`; deleted last of the rows.
// GLOBAL tables are deliberately NOT here: `signals` (shared operator ledger, keyed by `posted_by`)
// and `prices_cache` (shared market OHLC, no `user_id`) hold nothing private to one trader.
//
// ── Idempotency ─────────────────────────────────────────────────────────────────────────────────
// Every delete is scoped to the caller's verified uid, so a second call simply finds nothing: the
// row counts come back 0, the storage prefix is empty, and `deleteUser` on an already-gone user is
// treated as success. The function never 500s just because there was nothing left to remove.

/** Storage bucket that holds per-trader screenshots, path-prefixed by uid (migration 0010). */
export const SCREENSHOTS_BUCKET = 'trade-screenshots';

/**
 * Every row table the caller owns, child-first, with the column that scopes it to the caller.
 *
 * `column` is `user_id` for all but `profiles`, whose primary key IS the uid (`id`). The order is
 * load-bearing: a child is deleted before the parent it references so the explicit count is honest
 * and no statement depends on a cascade that a future migration might drop.
 */
export const TABLES: ReadonlyArray<{ table: string; column: string }> = [
  { table: 'ai_reviews', column: 'user_id' },
  { table: 'signal_follows', column: 'user_id' },
  { table: 'trade_sync_cursors', column: 'user_id' },
  { table: 'trades', column: 'user_id' },
  { table: 'broker_accounts', column: 'user_id' }, // cascades equity_snapshots
  { table: 'copy_settings', column: 'user_id' },
  { table: 'api_rate_limits', column: 'user_id' }, // daily-sync quota counter (migration 0011)
  { table: 'profiles', column: 'id' },
];

/** The bearer token from an `Authorization` header, or null when it is absent/malformed.
 *
 *  Pure and network-free so the "auth required" gate is testable without a Supabase project: the
 *  handler resolves the token to a uid with GoTrue, but a missing/garbled header can never produce
 *  one, and that decision lives here. */
export function parseBearer(authHeader: string | null): string | null {
  if (!authHeader) return null;
  const match = /^Bearer\s+(.+)$/i.exec(authHeader.trim());
  if (!match) return null;
  const token = match[1].trim();
  return token.length > 0 ? token : null;
}

/** Minimal shape of the Supabase client this module uses — the fake in the test implements it. */
export interface DeleteClient {
  from(
    table: string,
  ): {
    delete(opts: { count: 'exact' }): {
      eq(column: string, value: string): Promise<{ count: number | null; error: unknown }>;
    };
  };
  storage: {
    from(bucket: string): {
      list(
        path: string,
        opts?: unknown,
      ): Promise<{ data: Array<{ name: string; id: string | null }> | null; error: unknown }>;
      remove(paths: string[]): Promise<{ error: unknown }>;
    };
  };
  auth: {
    admin: {
      deleteUser(uid: string): Promise<{ error: unknown }>;
    };
  };
}

/** A thrown deletion failure carrying ONLY a short code — never a server body. */
export class DeleteError extends Error {
  readonly code: string;

  constructor(code: string) {
    super(code);
    this.name = 'DeleteError';
    this.code = code;
  }
}

/** The success summary the handler returns. `deleted` is a per-table row count. */
export interface DeleteSummary {
  ok: true;
  deleted: Record<string, number>;
  storage: number;
  user_deleted: boolean;
}

/** True when an admin `deleteUser` error just means the user is already gone — an idempotent
 *  success, not a failure. Inspected for control flow only; never logged or returned. */
export function isUserGone(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  const e = error as { status?: unknown; code?: unknown };
  return e.status === 404 || e.code === 404 || e.code === 'user_not_found' || e.code === '404';
}

/** Recursively list every object path under `prefix`. Folders (id === null) are descended into. */
async function listAllPaths(client: DeleteClient, bucket: string, prefix: string): Promise<string[]> {
  const { data, error } = await client.storage.from(bucket).list(prefix, {
    limit: 1000,
    offset: 0,
    sortBy: { column: 'name', order: 'asc' },
  });
  if (error || !data) return [];
  const paths: string[] = [];
  for (const entry of data) {
    const full = `${prefix}/${entry.name}`;
    if (entry.id === null) {
      // A folder: recurse. Screenshots live at `<uid>/<trade-id>/<file>`.
      paths.push(...(await listAllPaths(client, bucket, full)));
    } else {
      paths.push(full);
    }
  }
  return paths;
}

/** Deletes the caller's rows (child-first) and storage objects, scoped entirely to `uid`.
 *
 *  Returns the per-table counts and the number of storage objects removed. Throws [DeleteError]
 *  (code = the failing table, or 'storage') on the first hard error so the handler can answer 500
 *  with a safe message. Empty results are NOT errors — that is the idempotent case. */
export async function deleteAccountData(
  client: DeleteClient,
  uid: string,
): Promise<{ deleted: Record<string, number>; storage: number }> {
  const deleted: Record<string, number> = {};

  for (const { table, column } of TABLES) {
    const { count, error } = await client.from(table).delete({ count: 'exact' }).eq(column, uid);
    if (error) throw new DeleteError(table);
    deleted[table] = count ?? 0;
  }

  // Storage objects under the caller's uid prefix. Listed then removed; the bucket is private and
  // keyed on the first path segment (migration 0010), so this touches only the caller's files.
  const paths = await listAllPaths(client, SCREENSHOTS_BUCKET, uid);
  let removed = 0;
  if (paths.length > 0) {
    const { error } = await client.storage.from(SCREENSHOTS_BUCKET).remove(paths);
    if (error) throw new DeleteError('storage');
    removed = paths.length;
  }

  return { deleted, storage: removed };
}

/** Full deletion: rows + storage, then `auth.admin.deleteUser(uid)` LAST.
 *
 *  The auth user is removed only after its data, so a failure mid-way leaves an intact, signed-in
 *  account the trader can retry — never an orphaned login whose rows are half-gone. Idempotent: a
 *  second call deletes nothing and treats an already-deleted user as success. */
export async function runDelete(client: DeleteClient, uid: string): Promise<DeleteSummary> {
  const { deleted, storage } = await deleteAccountData(client, uid);

  const { error } = await client.auth.admin.deleteUser(uid);
  if (error && !isUserGone(error)) throw new DeleteError('deleteUser');

  return { ok: true, deleted, storage, user_deleted: true };
}

/** Maps an HTTP status onto a short, safe error token the client already understands. */
export function classifyStatus(status: number): string {
  switch (status) {
    case 401:
      return 'Unauthorized';
    case 405:
      return 'Method not allowed';
    case 503:
      return 'notConfigured';
    default:
      return 'server';
  }
}

