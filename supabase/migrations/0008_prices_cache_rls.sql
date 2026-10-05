-- TradeGuard Phase 2 — `prices_cache` read access (task 2.6).
--
-- `prices_cache` has existed since migration 0001 (`symbol`, `timeframe`, `ohlc jsonb`, `updated_at`,
-- primary key `(symbol, timeframe)`) and migration 0002 enabled RLS on it. But it never created a
-- POLICY — and with RLS enabled and no policy, Postgres denies every row to every non-superuser role.
-- That was harmless while nothing read the table; it becomes a hard blocker the moment the replay
-- ships, because `SupabasePriceBarRepository` reads it with the anon/publishable key and would get an
-- empty result set rather than an error. An empty result set is the dangerous failure here: the
-- client would render "no bars cached for this symbol" and the trader would conclude the backend was
-- broken, rather than being told the read was denied.
--
-- ── What this migration fixes ────────────────────────────────────────────────────────────────
--   1. A SELECT policy for authenticated users, so the replay can read cached bars.
--   2. A freshness index, so the staleness sweep does not scan.
--   3. An explicit REVOKE of writes from anon/authenticated, so the only writer is the
--      `market-bars` Edge Function under the service role.
--
-- ── Why price history is readable by any signed-in user ───────────────────────────────────────
-- OHLC candles for XAUUSD are public market facts; there is nothing per-user in a row. There is
-- deliberately NO `user_id` column here, and no policy keyed on one. Scoping the cache per user would
-- multiply metered TwelveData fetches by the size of the user base while storing identical data —
-- and, worse, it would imply to a future editor that these rows are private when they are not.
--
-- The write path is the part that needs care, and it is closed below: `prices_cache` accepts no
-- INSERT/UPDATE/DELETE from any client role. Without this, any user could POST bars into the shared
-- cache and every other trader's replay would chart invented prices — a cross-tenant data-poisoning
-- route that produces a backtest result, which is precisely the kind of number a trader might act on.
--
-- The writer is `supabase/functions/market-bars/index.ts`: it authenticates the caller with GoTrue
-- using their own bearer token, validates the symbol against a fixed allowlist, fetches from
-- TwelveData with the server-side key, normalises the response, and upserts on `(symbol, timeframe)`
-- so a refresh is idempotent.

-- ---------------------------------------------------------------------------------------------
-- 1. Read access
-- ---------------------------------------------------------------------------------------------

-- SELECT only, and only for authenticated sessions. `anon` stays excluded on purpose: an
-- unauthenticated caller must not be able to enumerate the cache by primary key.
create policy "read cached bars" on prices_cache
  for select
  to authenticated
  using (true);

-- The complement of the read policy. Belt and braces, because a policy added later by another
-- migration would otherwise be free to grant write access to this table.
revoke insert, update, delete on prices_cache from anon, authenticated;

comment on table prices_cache is
  'Cached OHLC bars keyed by (symbol, timeframe), written only by the market-bars Edge Function. '
  'Public market data — deliberately not scoped per user. ohlc is a jsonb array of {t,o,h,l,c} bars, '
  'oldest first. RLS is enabled; reads are granted to authenticated and writes to nobody.';

comment on column prices_cache.ohlc is
  'jsonb array of {t: ISO-8601, o,h,l,c: number}, oldest first. Written by market-bars, parsed by PriceBar.fromCacheList.';

-- ---------------------------------------------------------------------------------------------
-- 2. Freshness
-- ---------------------------------------------------------------------------------------------

-- `updated_at` is read on every replay to decide whether the cache is stale, and the primary key is
-- `(symbol, timeframe)`, so the planner serves that single-row lookup from the PK — no extra index is
-- needed for the read the client performs.
--
-- What DOES need an index is the sweep for series nobody has requested, which is ordered by age
-- across all rows. This index serves that directly.
create index if not exists prices_cache_updated_idx
  on prices_cache (updated_at desc);

comment on index prices_cache_updated_idx is
  'Supports the staleness sweep over prices_cache (which rows are oldest), not the single-row read.';

-- ---------------------------------------------------------------------------------------------
-- Verification notes
-- ---------------------------------------------------------------------------------------------
-- NOT executed against a live Supabase project in this environment. The behaviour above is reasoned
-- from Postgres/PostgREST semantics, not observed, so migration 0008 is NOT verified. Task 2.6 must
-- not be called live until the checks below have actually been run and passed.
--
-- The checks belong in `docs/BACKEND_DEPLOY.md` section 3a ("Gate: verify migration 0008"); they are
-- restated here so the migration and the deploy runbook cannot drift apart. Three points matter:
--
--   * Run them through POSTGREST, NOT the SQL Editor. In the SQL Editor you are `postgres`, which
--     BYPASSES RLS — so a `select count(*)` would ignore this policy entirely and the probe insert
--     would SUCCEED. Both would read as passes that prove nothing. Supabase's REST layer is the one
--     the app actually uses, so it is the one that must be exercised.
--
--   1. As a signed-in trader, GET /rest/v1/select=count with the anon `apikey` and the user's
--      `Authorization: Bearer` token returns the FULL row count, not zero. Zero here means this
--      policy is missing or wrong even though the rows exist — the silent failure this migration
--      exists to prevent.
--   2. The same GET with only the anon key returns count 0 (as data, not as a 401/403): RLS filters
--      silently, so an unauthenticated caller cannot enumerate the cache by primary key.
--   3. A signed-in trader's POST to /rest/v1/prices_cache FAILS with 401/403 — never 201. That is
--      the cross-tenant poisoning route this migration closes. If it ever returns 201, delete the row.
--
-- Re-running `supabase db push` is safe for the index, but `create policy` has no `if not exists` and
-- WILL fail on a second apply. Migrations 0004-0007 share this property. If this one must be
-- re-applied, uncomment the line below first:
--
--   drop policy if exists "read cached bars" on prices_cache;