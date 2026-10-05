-- TradeGuard Phase 2 — make the analytics views respect RLS (task 2.4).
--
-- Task 2.4 reads `v_patterns` for the pattern views + leaks screen. Migration 0002
-- created that view (and `v_daily_pnl`) *before* the task that reads them, and it
-- has a security problem that only becomes visible once a client queries it:
--
--   In Postgres, a view does NOT inherit the row-level security policies of the
--   tables it selects from. A plain `create view` runs with the privileges of its
--   OWNER (here `postgres`), so `select * from v_patterns` bypasses the
--   `own trades` policy on `trades` entirely and returns EVERY user's rows to
--   anyone who can query the view.
--
--   Nothing had read the view yet, so this was latent. As soon as the Flutter app
--   queries it — anonymously, with only the anon/publishable key — it becomes a
--   cross-account data leak: any user's pattern history, and therefore their
--   trading performance, readable by anyone who signs up.
--
-- The fix is `security_invoker = true` (Postgres 15+, which Supabase runs). It
-- makes the view execute as the CALLING role, so `trades`'s RLS policies are
-- evaluated per row and a user sees only their own journal.
--
-- The client also filters `eq('user_id', <session uid>)` (see
-- `SupabasePatternRepository`). That is deliberate defence in depth, NOT the
-- control that makes this safe: if the view were left non-invoker, the client-side
-- filter would still return other users' rows, because the policy simply would
-- not run. The database is the boundary; the client filter only narrows further.
--
-- Both views are recreated with `or replace` so the option is applied atomically.
-- Idempotent: re-running re-applies the same options.

create or replace view v_daily_pnl
  with (security_invoker = true)
as
select account_id,
       date_trunc('day', close_time) as day,
       sum(pnl) as pnl,
       count(*) as trades
from trades
group by 1, 2;

-- Unchanged definition — same columns, same aggregates, so the task 2.4 client
-- contract (`user_id, symbol, session, dow, hour, pnl, n, win_rate`) is untouched.
-- Only the execution privileges change.
create or replace view v_patterns
  with (security_invoker = true)
as
select user_id, symbol, session,
       extract(dow from close_time) as dow,
       extract(hour from close_time) as hour,
       sum(pnl) as pnl,
       count(*) as n,
       avg(case when pnl > 0 then 1 else 0 end) as win_rate
from trades
group by 1,2,3,4,5;

-- The views expose no credentials and no broker identifiers, but they are still
-- user trading history. Grant only to the authenticated role; `anon` has no
-- business reading either the trades or their aggregates.
revoke all on v_daily_pnl from anon;
revoke all on v_patterns from anon;
grant select on v_daily_pnl to authenticated;
grant select on v_patterns to authenticated;

-- NOTE (human gate): this migration has NOT been executed against a live Supabase
-- project in this environment, so the RLS behaviour of the views is reasoned from
-- the Postgres semantics above rather than observed. Verify with
-- `supabase db push` then a two-user check — sign in as trader A, confirm
-- `select count(*) from v_patterns` equals A's own trade count, and repeat as B.