-- TradeGuard Phase 2 — `sync-trades` state and schedule (task 2.2).
--
-- Two things live here:
--   1. `trade_sync_cursors` — per-account incremental-sync watermarks. Trades themselves are
--      already in `trades`; this table records only *how far we have read*, and must never hold
--      provider credentials or trade data.
--   2. The cron schedule for `sync-trades`, matching the pattern migration 0004 established
--      for `guard-check`.
--
-- Why a cursor table at all: MetaAPI is metered. Without a watermark every 5-minute run would
-- re-read the account's entire history, exhausting the allowance and hammering the broker. The
-- cursor makes each run incremental while `trades.unique (user_id, external_id)` makes it
-- idempotent — the timestamp only narrows the window, the unique key guarantees correctness.

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- ---------------------------------------------------------------------------------------------
-- 0. Correct the trades dedupe key  (REQUIRED before sync-trades can work)
-- ---------------------------------------------------------------------------------------------
--
-- Migration 0001 declared `unique (user_id, external_id)`. That key is wrong for broker data:
-- a deal/ticket id is unique only *within one broker account*, not across all of a trader's
-- accounts. A trader with an FTMO and an Exness account will have a deal `12345` in both, and
-- the old key would make the second sync UPDATE the first account's row — silently moving a
-- trade between accounts and corrupting both journals.
--
-- `account_id` is the correct tenant-scoped key, and it is also what the client already uses
-- (`InMemoryTradeImportRepository`, `TradeRecord.externalId` + the account id), so this change
-- makes the database agree with the code instead of the other way round.
--
-- Idempotent: safe to re-apply.
--
-- This MUST be `alter table ... drop constraint`, not `drop index`. Migration 0001 declared the
-- key inline (`unique (user_id, external_id)`), so what exists is a TABLE CONSTRAINT
-- `trades_user_id_external_id_key` that happens to have a backing index of the same name. Postgres
-- refuses to drop that index out from under its owning constraint:
--
--     ERROR: cannot drop index trades_user_id_external_id_key because constraint
--            trades_user_id_external_id_key on table trades requires it  (SQLSTATE 2BP01)
--
-- Dropping the constraint removes the index with it. `if exists` keeps this safe to re-apply, and
-- safe to run against a database where the constraint was never present.
alter table trades drop constraint if exists trades_user_id_external_id_key;

-- Refuse to proceed if real duplicates already exist, rather than failing later with an opaque
-- unique-violation. Duplicates can only pre-date this migration, and only when the trader had a
-- single account, so there is nothing legitimate to merge.
do $$
declare
  dupes bigint;
begin
  select count(*) into dupes
  from (
    select account_id, external_id
    from trades
    where external_id is not null
    group by account_id, external_id
    having count(*) > 1
  ) d;

  if dupes > 0 then
    raise exception
      'sync-trades: % duplicate (account_id, external_id) group(s) must be resolved before '
      'creating the unique index', dupes;
  end if;
end $$;

create unique index if not exists trades_account_external_unique
  on trades (account_id, external_id);

comment on index trades_account_external_unique is
  'Broker sync/import dedupe key: a deal id is unique per broker account, not per user.';

-- ---------------------------------------------------------------------------------------------
-- 1. Cursor state
-- ---------------------------------------------------------------------------------------------

create table if not exists trade_sync_cursors (
  -- The account this cursor belongs to. Deleting the account removes its sync state.
  account_id uuid primary key references broker_accounts(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,

  -- Watermark: trades at or before this instant are considered read. NULL = never synced, which
  -- makes the first run back-fill a bounded window rather than all history.
  last_synced_at timestamptz,
  last_external_id text,
  last_run_at timestamptz,
  consecutive_failures int not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table trade_sync_cursors is
  'Per-account incremental-sync watermark for sync-trades. Holds progress only, never provider credentials.';

-- The cron worker scans by "last run / failures" to decide what is due and who is backing off.
create index if not exists idx_sync_cursors_due
  on trade_sync_cursors (last_run_at, consecutive_failures);

-- RLS, matching the pattern used for `trades` and `broker_accounts`.
alter table trade_sync_cursors enable row level security;

-- A user may read and advance ONLY their own account's cursor. The column check makes this
-- defence-in-depth: even if `broker_accounts.user_id` were ever wrong, a user cannot attach a
-- cursor to somebody else's account.
create policy "own sync cursors" on trade_sync_cursors
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Keep `updated_at` honest. `sync-trades` writes with the service role, which bypasses RLS but
-- NOT this trigger, so the column stays correct either way.
create or replace function public.touch_sync_cursor_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_sync_cursor_updated_at on trade_sync_cursors;
create trigger trg_sync_cursor_updated_at
  before update on trade_sync_cursors
  for each row execute function public.touch_sync_cursor_updated_at();

-- ---------------------------------------------------------------------------------------------
-- 2. Schedule `sync-trades`
-- ---------------------------------------------------------------------------------------------

-- Drop any previous schedule first: re-applying this migration must not leave two jobs, or the
-- job would double-sync every account.
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'sync-trades-5min';
exception
  when undefined_table or invalid_schema_name then null;
end $$;

-- Every 5 minutes, matching `docs/BACKEND_SCHEMA.md`.
--
-- The service-role key is read from Vault AT RUN TIME, exactly as in migration 0004. It is never
-- interpolated into `cron.job.command` because that column is readable by anything with SQL
-- access, and a literal key there would leak to every role that can `select * from cron.job`.
--
-- Requires the same two Vault secrets as `guard-check`:
--   project_url       = https://<project-ref>.supabase.co
--   service_role_key  = the service_role key
select cron.schedule(
  'sync-trades-5min',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := (
      select decrypted_secret from vault.decrypted_secrets where name = 'project_url'
    ) || '/functions/v1/sync-trades',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'
      )
    ),
    body := '{}'::jsonb,
    -- Trade sync pages through MetaAPI, so it needs a longer ceiling than guard-check's 50s.
    timeout_milliseconds := 55000
  );
  $$
);