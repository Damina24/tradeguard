-- TradeGuard Phase 3 — copy-signal schema (tasks 3.5/3.6 prerequisite).
--
-- The `copy-signal` Edge Function and its guardrail policy are already implemented and unit-tested
-- (supabase/functions/copy-signal/{index.ts,shared.ts,copy_signal_test.ts}), but the function is
-- not runnable against the schema this project actually has: it reads and writes three elements
-- that no migration ever created. This migration adds exactly those three and nothing else — the
-- guardrail policy itself lives in `shared.ts` (pure, fixture-tested on both the TS and Dart
-- sides) and is deliberately NOT duplicated in SQL.
--
--   1. `broker_accounts.copy_enabled` — index.ts selects `id,metaapi_account_id,copy_enabled,
--      initial_balance` for the caller's accounts, and `evaluateAccount` reads it as
--      `row?.copy_enabled === true` (per-account permission, OFF by default). Without the column
--      every copy request dies at the account read.
--   2. `copy_settings` — index.ts reads
--      `live_consent,kill_switch,max_lots,max_concurrent_follows` scoped to the verified caller.
--      Without the table every copy request dies at the settings read.
--   3. `signal_follows.order_id` — the LIVE branch inserts the broker's order id alongside the
--      follow. Without the column a live insert fails AFTER the broker order is already out: the
--      order reaches the trader's account while our ledger records nothing — the exact failure
--      mode index.ts calls out ("report the write failure honestly rather than pretending the
--      ledger recorded it").
--
-- ── Defaults are DEFAULT_SETTINGS, verbatim ─────────────────────────────────────────────────────
-- `copy_settings` column defaults mirror `DEFAULT_SETTINGS` in `copy-signal/shared.ts`
-- (liveConsent: false, killSwitch: false, maxLots: 5.0, maxConcurrentFollows: 5). The function
-- treats an ABSENT row identically — index.ts falls back to those same four values — so "no row"
-- and "row at defaults" are the same contract, and the column defaults keep the database honest
-- about it. Paper is the default posture everywhere: consent OFF, kill switch OFF (nothing to
-- kill yet), conservative caps.
--
-- ── What is deliberately NOT here ───────────────────────────────────────────────────────────────
--   * No guardrail logic in SQL: paper-default / kill-switch / consent / per-account permission /
--     max-lots / concurrent caps are enforced by `evaluateAccount` (shared.ts), unit-tested in
--     copy_signal_test.ts. This migration only stores the facts it reads.
--   * No client UI (task 3.4), no wiring changes to the function (task 3.5) — schema only.
--   * No `updated_at` trigger: no migration in this project uses one; `prices_cache.updated_at`
--     follows the same "the writer sets it" convention, and `copy_settings` writers are expected
--     to do likewise.

-- ---------------------------------------------------------------------------------------------
-- 1. Per-account permission — broker_accounts.copy_enabled
-- ---------------------------------------------------------------------------------------------

alter table broker_accounts
  add column if not exists copy_enabled boolean not null default false;

comment on column broker_accounts.copy_enabled is
  'Per-account copy permission for copy-signal (task 3.6). OFF by default: evaluateAccount refuses '
  'with ''accountDisabled'' unless this is true. Read by the Edge Function under the service role; '
  'toggled by the owner under the ''own accounts'' policy.';

-- ---------------------------------------------------------------------------------------------
-- 2. Trader settings — copy_settings
-- ---------------------------------------------------------------------------------------------

-- One row per trader, created lazily by the writer (there is deliberately no signup trigger: the
-- function already handles an absent row as "all defaults", so a row only needs to exist once the
-- trader changes something). user_id is the PRIMARY KEY — the only read in the codebase is
-- `.eq('user_id', userId).limit(1)`, so a second row per trader would be a contradiction.
create table if not exists copy_settings (
  user_id uuid primary key references profiles(id) on delete cascade,
  live_consent boolean not null default false,
  kill_switch boolean not null default false,
  max_lots numeric not null default 5.0,
  max_concurrent_follows int not null default 5,
  updated_at timestamptz not null default now()
);

comment on table copy_settings is
  'One row per trader''s copy-signal settings (tasks 3.5/3.6). Absent row == defaults, exactly as '
  'copy-signal/index.ts falls back to DEFAULT_SETTINGS. Read by the Edge Function under the '
  'service role; read/written by the owner under the ''own copy settings'' policy.';

comment on column copy_settings.live_consent is
  'Stored consent for LIVE copy trading (task 3.6). Absent row or false = live is refused with '
  '''consentRequired'', never silently downgraded to paper.';

comment on column copy_settings.kill_switch is
  'Kill switch: when true copy-signal refuses EVERY follow, paper included.';

comment on column copy_settings.max_lots is
  'Per-follow lot cap; matches DEFAULT_MAX_LOTS (5.0) in copy-signal/shared.ts. Over the cap is '
  'refused (''maxLots''), never silently clamped.';

comment on column copy_settings.max_concurrent_follows is
  'Concurrent open-follow cap; matches DEFAULT_MAX_CONCURRENT_FOLLOWS (5) in '
  'copy-signal/shared.ts.';

comment on column copy_settings.updated_at is
  'When the trader last changed a setting. Set by the writer (no trigger — same convention as '
  'prices_cache.updated_at).';


-- ---------------------------------------------------------------------------------------------
-- 3. RLS — own settings, and nothing else
-- ---------------------------------------------------------------------------------------------

alter table copy_settings enable row level security;

-- Same shape as the "own profile / own accounts / own trades / own follows" policies in migration
-- 0002: a trader may read and write exactly their own row and no other. `with check` matters as
-- much as `using` here — without it an authenticated user could change user_id on a row they
-- touch and write under someone else's id, flipping another trader's kill switch or live consent.
--
-- The Edge Function is unaffected: it reads with the service role, which bypasses RLS, and it
-- scopes that read on the verified JWT's id itself (index.ts).
--
-- `drop policy if exists` first because `create policy` has no `if not exists` — this keeps the
-- migration re-appliable (0007 does the same).
drop policy if exists "own copy settings" on copy_settings;

create policy "own copy settings" on copy_settings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------------------------
-- 4. Ledger — signal_follows.order_id
-- ---------------------------------------------------------------------------------------------

-- text, NOT uuid: the value is whatever MetaAPI returns (`orderId ?? positionId ?? id`, and the
-- literal string 'accepted' when a 2xx body was unparseable) — an opaque broker identifier with
-- no uuid guarantee.
--
-- NULLABLE, because the paper branch of index.ts never includes the column in its insert payload
-- (a simulated fill has no broker order), while the live branch always does. That is the existing
-- execution contract read off the function, not a guess.
alter table signal_follows
  add column if not exists order_id text;

comment on column signal_follows.order_id is
  'Broker order id written by copy-signal LIVE follows only (MetaAPI orderId ?? positionId ?? id, '
  'or ''accepted'' when a 2xx body was unparseable). Paper follows never set it and stay NULL.';

-- The contract, enforced: a persisted row with mode=''live'' must carry an order id. index.ts
-- guarantees this on the write path — a live result whose order id came back null is reported as
-- ''failed'' and never inserted, and the paper branch never includes the column — so the check is
-- the schema's copy of exactly that existing behaviour, not new policy.
--
-- Written defensively, migration 0007 style: pre-existing violations are refused LOUDLY rather
-- than silently picked over, and the constraint is skipped when it already exists so re-applying
-- the migration is safe.
do $$
declare
  bad bigint;
begin
  select count(*) into bad
  from signal_follows
  where mode = 'live' and order_id is null;

  if bad > 0 then
    raise exception
      'signal_follows: % live row(s) without an order_id must be resolved before adding the '
      'signal_follows_live_needs_order_id check', bad;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'signal_follows_live_needs_order_id'
      and conrelid = 'signal_follows'::regclass
  ) then
    alter table signal_follows
      add constraint signal_follows_live_needs_order_id
      check (mode <> 'live' or order_id is not null);
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- Verification notes
-- ---------------------------------------------------------------------------------------------
-- NOT executed against a live Supabase project in this environment (Docker is unavailable here,
-- so neither the local stack nor `supabase db push` was applied — deliberately: this task does
-- not deploy). The migration was validated structurally instead: every statement is guarded
-- (`if not exists` / `drop policy if exists` / DO-block guards), the copy-signal suite passes,
-- and `supabase db push --dry-run` sees 0009 as the pending migration without applying it. To
-- verify after an actual `supabase db push`:
--
--   * As trader A: `select copy_enabled from broker_accounts where id = <own>` returns false for a
--     freshly connected account (OFF by default).
--   * As trader A: insert into copy_settings (user_id) values (auth.uid()) on conflict do nothing;
--     then `select * from copy_settings` shows live_consent=false, kill_switch=false,
--     max_lots=5.0, max_concurrent_follows=5 — the DEFAULT_SETTINGS quartet.
--   * As trader B: A's copy_settings row returns 0 rows through POSTGREST (not via the SQL Editor,
--     where you are `postgres` and BYPASS RLS — see the 0008 gate notes for why that distinction
--     is the whole point).
--   * A paper follow insert succeeds with order_id NULL; a live row without an order_id fails the
--     signal_follows_live_needs_order_id check.
--
-- Re-running `supabase db push` is safe for every statement here: the ALTERs are `if not exists`,
-- the policy is dropped first, and the check constraint is DO-block guarded — unlike migrations
-- 0004-0008, this one carries no "create policy is not idempotent" caveat.
