-- TradeGuard Phase 2 — `ai_reviews` hardening (task 2.5).
--
-- Task 2.5 makes `ai-review` the first writer of `ai_reviews`, which turns two latent problems in
-- migration 0002 into live ones. Both are fixed here.
--
-- ── 1. The client could fabricate its own AI reviews ──────────────────────────────────────────
-- Migration 0002 declared:
--
--     create policy "own reviews" on ai_reviews
--       for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
--
-- `for all` covers INSERT and UPDATE, not just SELECT. Until now nothing in the app wrote to this
-- table, so the policy was merely over-broad. The moment the AI Review card exists, it becomes a
-- correctness and trust problem: the app holds only the anon/publishable key, so any user could
-- `insert` an `ai_reviews` row with `user_id = auth.uid()` and any summary, score and suggestions
-- they liked. The card would then render that fabricated text as though a language model had
-- written it — and a user could raise their own stored score, or delete a real review to hide it.
--
-- The fix is least privilege: a user may READ their own reviews, and nothing more. Every write now
-- comes from the `ai-review` Edge Function, which authenticates the caller with GoTrue and then
-- writes with the service role. That inverts the usual risk — the service role bypasses RLS, so
-- the function is now the single place where ownership must be enforced, and it does so by taking
-- `user_id` from the VERIFIED JWT (never from the request body) and filtering the `trades` read on
-- the same id. See `supabase/functions/ai-review/index.ts`.
--
-- ── 2. No idempotency key, so a second request duplicated the review ─────────────────────────
-- The handler upserts on `(user_id, trade_id)`, which requires a matching unique index. Without it
-- the ON CONFLICT clause has nothing to resolve against and every tap of "Get AI review" would add
-- another row for the same trade. Reviews are one-per-trade by definition — the trade's facts do
-- not change once it is closed — so the key is exactly the trade, scoped to its owner.
--
-- Adding it is safe on a table that has never been written to, but this is written defensively: a
-- pre-existing duplicate pair is refused loudly rather than silently picking a winner, because
-- silently deleting a row would be a destructive surprise on someone's real data.

alter table ai_reviews add column if not exists prompt_version text;

comment on column ai_reviews.prompt_version is
  'Prompt contract the review was generated under (TRD §7: prompts are versioned in source).';

-- ---------------------------------------------------------------------------------------------
-- 1. Idempotency key
-- ---------------------------------------------------------------------------------------------

do $$
declare
  dupes bigint;
begin
  select count(*) into dupes
  from (
    select user_id, trade_id
    from ai_reviews
    where trade_id is not null
    group by 1, 2
    having count(*) > 1
  ) d;

  if dupes > 0 then
    raise exception
      'ai_reviews: % duplicate (user_id, trade_id) group(s) must be resolved before creating the '
      'unique index', dupes;
  end if;
end $$;

create unique index if not exists ai_reviews_user_trade_unique
  on ai_reviews (user_id, trade_id)
  where trade_id is not null;

comment on index ai_reviews_user_trade_unique is
  'One AI review per (owner, trade): makes ai-review idempotent and is the ON CONFLICT target.';

-- Reads are "newest review for each of my trades", which this index serves directly.
create index if not exists ai_reviews_user_created_idx
  on ai_reviews (user_id, created_at desc);

-- ---------------------------------------------------------------------------------------------
-- 2. Least privilege — drop the writable policy
-- ---------------------------------------------------------------------------------------------

drop policy if exists "own reviews" on ai_reviews;

-- SELECT only. Split from the write path on purpose: the single writable path is now the Edge
-- Function under the service role, which is authenticated separately.
--
-- `using (auth.uid() = user_id)` is the RLS boundary that scopes rows. A review belonging to
-- another trader is never returned — and because this is a base table (not a view), that policy
-- is enforced; no `security_invoker` option is involved or needed here.
create policy "own reviews read" on ai_reviews
  for select
  using (auth.uid() = user_id);

-- The journal UI only ever displays reviews; it never edits or removes one. A trader deleting a
-- real review to hide it is not a flow this product has.
revoke insert, update, delete on ai_reviews from anon, authenticated;

-- `purge-account` and the account-deletion flow still work: they run with the service role, which
-- is not affected by RLS or by these REVOKEs, and `ai_reviews.user_id` cascades from `profiles`
-- on delete anyway (docs/ACCOUNT_DELETION.md already lists AI reviews as deleted data).

-- ---------------------------------------------------------------------------------------------
-- Verification notes
-- ---------------------------------------------------------------------------------------------
-- NOT executed against a live Supabase project in this environment. The behaviour above is reasoned
-- from Postgres/PostgREST semantics, not observed. To verify after `supabase db push`:
--
--   * As trader A, `select count(*) from ai_reviews;` returns only A's rows.
--   * As trader A, an `insert into ai_reviews (user_id, trade_id, summary, score) values
--     (auth.uid(), <uuid>, 'forged', 100)` FAILS with a permission error — the regression this
--     migration exists to close.
--   * As trader B, A's `trade_id` returns 404 from `ai-review`, not a review.
--   * Re-running `supabase db push` is safe: every statement is `if not exists` / `if exists`.