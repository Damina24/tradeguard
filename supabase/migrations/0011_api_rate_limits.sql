-- TradeGuard Phase 2 — per-user daily rate limit for on-demand live broker syncs.
--
-- Business driver: MetaAPI is a METERED provider — every live read of balance/equity/positions
-- and every closed-deal pull costs us credits. `sync-trades` (cron, migration 0005) already
-- protects the shared allowance with per-account backoff and an eligibility window, but
-- `sync-account-data` is USER-facing and on demand: a single trader mashing refresh — or a
-- script replaying the endpoint with their own JWT — could drain the whole project's MetaAPI
-- allowance in minutes. This table is the per-user, per-day counter that caps that.
--
-- Design:
--   * One row per (user_id, UTC calendar date). The `date` column is a plain DATE holding the
--     UTC day, so the counter RESETS AT UTC MIDNIGHT for free — a new day is simply a new row,
--     with no rolling window to sweep or expire. "Try again tomorrow" is literally true.
--   * (user_id, date) is the PRIMARY KEY, which is also the ON CONFLICT target the increment
--     upserts against, so the counter is unique and idempotent per user per day.
--   * Writes happen ONLY through the `consume_sync_quota` RPC below, called by the Edge Function
--     with the service role. RLS is enabled with NO policy, so no client role can read or write a
--     row directly; the service role (and the security-definer function) bypass RLS.
--
-- The counter is incremented ONLY when a request is allowed, and only immediately before the Edge
-- Function spends a MetaAPI call — an unlinked account or a 404 (a trader probing an account_id
-- that is not theirs) never reaches the counter, because neither spends MetaAPI credits.

create table if not exists api_rate_limits (
  user_id uuid not null references profiles(id) on delete cascade,
  -- UTC calendar day. A plain date, not timestamptz: this is what makes the counter reset at UTC
  -- midnight. Computed server-side in consume_sync_quota as (now() at time zone 'utc')::date,
  -- never from the client, so a caller cannot pin or roll back their own window.
  date date not null,
  request_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, date)
);

comment on table api_rate_limits is
  'Per-user, per-UTC-day counter capping on-demand live broker reads (sync-account-data). Protects the metered MetaAPI allowance from a single user looping refresh. Written only by the consume_sync_quota RPC under the service role.';

comment on column api_rate_limits.date is
  'UTC calendar day (now() at time zone ''utc''). A new day is a new row, so the counter resets at UTC midnight with no sweep.';

comment on column api_rate_limits.request_count is
  'Successful live-data syncs this user has consumed today. Incremented atomically by consume_sync_quota, only while under the daily limit.';

-- Least privilege: the counter is internal. Enable RLS and grant NOTHING to client roles — with
-- RLS on and no policy, anon/authenticated see and touch zero rows. The Edge Function writes via
-- the service role, which bypasses RLS. The explicit REVOKEs are belt-and-braces on top of that
-- (mirrors migration 0007 on ai_reviews).
alter table api_rate_limits enable row level security;

revoke insert, update, delete on api_rate_limits from anon, authenticated;

-- Forward-looking retention index: a nightly sweep that deletes days older than N would order by
-- date; this serves it without a scan. Harmless today (the table is tiny and self-limiting),
-- present so a retention job never needs a migration of its own.
create index if not exists api_rate_limits_date_idx on api_rate_limits (date);

-- ---------------------------------------------------------------------------------------------
-- Atomic consume: check-and-increment in ONE statement, no read-then-write race.
-- ---------------------------------------------------------------------------------------------
-- Returns the NEW request_count (>= 1) when the request is allowed and the counter was consumed,
-- or 0 when the user is already at the daily limit (nothing is incremented in that case).
--
-- The single upsert is what makes this race-free: two concurrent syncs for the same user cannot
-- both slip past the limit, because Postgres serialises them on the (user_id, date) row lock and
-- the `where request_count < p_limit` guard refuses the increment the moment the cap is reached.
--
-- security definer + a pinned search_path, matching public.touch_sync_cursor_updated_at (0005):
-- the function owns the write so RLS never has to be reasoned about at the call site.
create or replace function public.consume_sync_quota(p_user_id uuid, p_limit int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'utc')::date;
  v_count int;
begin
  -- A non-positive limit means "block everything"; never let an insert slip a request through.
  if p_limit is null or p_limit <= 0 then
    return 0;
  end if;

  insert into api_rate_limits (user_id, date, request_count, updated_at)
  values (p_user_id, v_today, 1, now())
  on conflict (user_id, date)
  do update set request_count = api_rate_limits.request_count + 1,
                updated_at = now()
  where api_rate_limits.request_count < p_limit
  returning request_count into v_count;

  -- FOUND is true only when the insert or the guarded update produced a row. When the user is
  -- already at the cap the DO UPDATE is skipped by its WHERE, RETURNING yields nothing, and we
  -- fall through to 0 — quota NOT consumed.
  if found then
    return v_count;
  end if;

  return 0;
end;
$$;

comment on function public.consume_sync_quota(uuid, int) is
  'Atomically consumes one live-sync credit for (user, UTC day). Returns the new count on success, 0 when the daily limit is already reached. Guarded so it is race-free.';

-- Only the service role (and the security-definer owner) may call it; clients get nothing.
revoke all on function public.consume_sync_quota(uuid, int) from public, anon, authenticated;
grant execute on function public.consume_sync_quota(uuid, int) to service_role;

