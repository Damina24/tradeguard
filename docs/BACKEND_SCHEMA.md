# BACKEND_SCHEMA.md — TradeGuard (Supabase/Postgres)

## 1. Tables

```sql
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  email text,
  plan text not null default 'free',           -- free|pro|elite|lifetime
  rc_customer_id text,
  onboarded boolean not null default false,
  created_at timestamptz not null default now()
);

create table broker_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  platform text not null,                       -- mt4|mt5|ctrader
  metaapi_account_id text,
  nickname text not null,
  prop_firm text,
  phase text not null default 'eval',           -- eval|funded|personal
  currency text not null default 'USD',
  initial_balance numeric not null default 0,
  profit_target numeric,
  daily_loss_limit numeric,
  max_drawdown numeric,
  drawdown_type text not null default 'static', -- static|trailing
  equity_guard_enabled boolean not null default false,
  copy_enabled boolean not null default false,      -- per-account copy permission (migration 0009)
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table trades (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  account_id uuid not null references broker_accounts(id) on delete cascade,
  external_id text,
  symbol text not null,
  direction text not null,                      -- long|short
  lots numeric not null,
  entry numeric, exit numeric, sl numeric, tp numeric,
  open_time timestamptz, close_time timestamptz,
  pnl numeric not null default 0,
  commission numeric not null default 0,
  swap numeric not null default 0,
  mfe numeric, mae numeric,
  setup text, session text,                     -- london|newyork|asia
  grade text,                                   -- A|B|C|D
  notes text, screenshot_url text,
  created_at timestamptz not null default now(),
  unique (user_id, external_id)
);

create table equity_snapshots (
  id bigserial primary key,
  account_id uuid not null references broker_accounts(id) on delete cascade,
  equity numeric not null, balance numeric not null,
  drawdown_used numeric not null default 0,
  daily_pnl numeric not null default 0,
  peak_equity numeric not null default 0,   -- added in migration 0003
  created_at timestamptz not null default now()
);
```

## 2. Tables (signals, follows, AI, cache)

```sql
create table signals (
  id uuid primary key default gen_random_uuid(),
  pair text not null, direction text not null,
  entry numeric, sl numeric, tp1 numeric, tp2 numeric, tp3 numeric,
  confidence int, rationale text,
  status text not null default 'active',        -- active|closed|cancelled
  result_pips numeric,
  premium boolean not null default false,
  posted_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table signal_follows (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  signal_id uuid not null references signals(id) on delete cascade,
  account_id uuid not null references broker_accounts(id) on delete cascade,
  lots numeric, risk_pct numeric,
  mode text not null default 'paper',           -- paper|live
  copy_status text not null default 'pending',  -- pending|placed|filled|failed|closed
  order_id text,                                -- broker order id; LIVE rows only, paper rows NULL (migration 0009)
  pnl numeric default 0,
  created_at timestamptz not null default now()
);

create table copy_settings (
  user_id uuid primary key references profiles(id) on delete cascade,
  live_consent boolean not null default false,           -- live copy consent (task 3.6)
  kill_switch boolean not null default false,            -- blocks ALL follows when true
  max_lots numeric not null default 5.0,                 -- = DEFAULT_MAX_LOTS
  max_concurrent_follows int not null default 5,         -- = DEFAULT_MAX_CONCURRENT_FOLLOWS
  updated_at timestamptz not null default now()
);

create table ai_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  trade_id uuid references trades(id) on delete cascade,
  summary text, leak text, score int, suggestions jsonb,
  model text, created_at timestamptz not null default now()
);

create table prices_cache (
  symbol text not null, timeframe text not null,
  ohlc jsonb not null, updated_at timestamptz not null default now(),
  primary key (symbol, timeframe)
);
```

### `prices_cache` — the backtest bar cache (task 2.6)

| Column | Type | Contract |
|---|---|---|
| `symbol` | text | Upper-case canonical form from a fixed allowlist (`XAUUSD`, `EURUSD`, `GBPUSD`, `USDJPY`, `US30`) |
| `timeframe` | text | One of `15min`, `1h`, `4h`, `1day` — TwelveData's own wire values |
| `ohlc` | jsonb | Array of `{t, o, h, l, c}`, **oldest first**; `t` is an ISO-8601 UTC instant |
| `updated_at` | timestamptz | When `market-bars` wrote the row; the client's staleness check reads it |

Three properties that are deliberate rather than incidental:

- **Deliberately NOT scoped per user.** OHLC candles are public market facts; there is no per-user
  data in a row and no `user_id` column. Scoping the cache per user would multiply metered TwelveData
  fetches by the size of the user base while storing identical data — and would imply to a later
  editor that these rows are private.
- **Writes are service-role only.** Migration 0008 opens a SELECT policy for `authenticated` and
  revokes INSERT/UPDATE/DELETE from `anon` and `authenticated`. Without the revoke, any user could
  POST bars into the shared cache and every other trader's replay would chart invented prices — a
  cross-tenant poisoning route that produces a *backtest result*, which is precisely the kind of
  number a trader might act on.
- **`market-bars` normalises to UTC.** TwelveData's timestamps carry no zone, and `new Date(...)` reads
  a naive timestamp as LOCAL time. Since the normalised bars land in one shared row, two users in
  different timezones would otherwise replay different series for the same symbol. Naive timestamps are
  pinned to UTC so the cache holds one canonical answer.

### `copy_settings`, `broker_accounts.copy_enabled`, `signal_follows.order_id` (migration 0009)

The schema half of the `copy-signal` contract (tasks 3.5/3.6). The guardrail *policy* lives in
`supabase/functions/copy-signal/shared.ts` (`evaluateAccount`, unit-tested in
`copy_signal_test.ts`) — this migration only stores the facts it reads, and deliberately does not
duplicate any rule in SQL.

| Element | Type | Contract |
|---|---|---|
| `broker_accounts.copy_enabled` | boolean, NOT NULL, default `false` | Per-account permission. `evaluateAccount` reads it as `row?.copy_enabled === true`; off by default, refusal `accountDisabled`. Toggled by the owner under `own accounts`. |
| `copy_settings.user_id` | uuid, PK → `profiles(id)` on delete cascade | One row per trader, created lazily — an **absent row means "all defaults"** (index.ts falls back to `DEFAULT_SETTINGS`). |
| `copy_settings.live_consent` | boolean, NOT NULL, default `false` | Stored live consent. Requesting `mode: 'live'` without it is a refusal (`consentRequired`), never a silent downgrade to paper. |
| `copy_settings.kill_switch` | boolean, NOT NULL, default `false` | When `true`, copy-signal refuses **every** follow, paper included. |
| `copy_settings.max_lots` | numeric, NOT NULL, default `5.0` | Mirrors `DEFAULT_MAX_LOTS`. Over the cap is refused (`maxLots`), never clamped. |
| `copy_settings.max_concurrent_follows` | int, NOT NULL, default `5` | Mirrors `DEFAULT_MAX_CONCURRENT_FOLLOWS`. |
| `copy_settings.updated_at` | timestamptz, NOT NULL, default `now()` | Set by the writer (no trigger — same convention as `prices_cache.updated_at`). |
| `signal_follows.order_id` | text, **nullable** | Broker order id (`orderId ?? positionId ?? id`, else the literal `'accepted'` on an unparseable 2xx). **Live rows always carry one** — a null order id is reported `failed` and never inserted — and **paper rows are always NULL**, because the paper branch omits the column entirely. Enforced by the `signal_follows_live_needs_order_id` check (`mode <> 'live' or order_id is not null`). |

Three properties that are deliberate:

- **The four `copy_settings` defaults are `DEFAULT_SETTINGS`, verbatim.** The function treats a
  missing row and a row at defaults identically, so the column defaults keep the database honest
  about that equivalence. Paper is the default posture everywhere: consent OFF, kill switch OFF,
  conservative caps.
- **RLS is own-row only** (`own copy settings`, `for all using/check auth.uid() = user_id`) — the
  same shape as `own accounts`/`own follows` in migration 0002. `copy_settings` is read by the
  Edge Function under the service role (which bypasses RLS) scoped to the verified JWT id, so the
  policy only has to constrain client sessions. A missing `with check` would let a trader write
  under another trader's `user_id` — i.e. flip someone else's kill switch.
- **`order_id` is text, not uuid** — MetaAPI's identifier (or the `'accepted'` stand-in) has no
  uuid guarantee. Its nullability is the paper/live execution contract read off `index.ts`, not a
  convention: nullable overall, NOT NULL-for-live via the check constraint.

## 3. Indexes

```sql
create index on trades (account_id, close_time desc);
create index on equity_snapshots (account_id, created_at desc);
create index on signals (status, created_at desc);
create index on signal_follows (user_id, created_at desc);
```

## 4. RLS

```sql
alter table profiles enable row level security;
alter table broker_accounts enable row level security;
alter table trades enable row level security;
alter table equity_snapshots enable row level security;
alter table signal_follows enable row level security;
alter table ai_reviews enable row level security;
alter table signals enable row level security;
alter table prices_cache enable row level security;
alter table copy_settings enable row level security;

create policy "own profile" on profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

create policy "own accounts" on broker_accounts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own trades" on trades
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own follows" on signal_follows
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own copy settings" on copy_settings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own reviews" on ai_reviews
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own snapshots" on equity_snapshots for select using (
  exists (select 1 from broker_accounts a where a.id = account_id and a.user_id = auth.uid())
);

create policy "signals read" on signals
  for select using (auth.role() = 'authenticated');
```

## 5. Views

```sql
create view v_daily_pnl as
select account_id, date_trunc('day', close_time) as day, sum(pnl) as pnl, count(*) as trades
from trades group by 1,2;

create view v_patterns as
select user_id, symbol, session,
       extract(dow from close_time) as dow,
       extract(hour from close_time) as hour,
       sum(pnl) as pnl, count(*) n,
       avg(case when pnl>0 then 1 else 0 end) as win_rate
from trades group by 1,2,3,4,5;
```

Migration **0006** recreates both views with `with (security_invoker = true)` and restricts
`select` to `authenticated` (`anon` revoked). Without it a view runs with its owner's
privileges, bypassing the `own trades` policy on `trades` — which would expose every user's
pattern history. Read by task 2.4; see the migration for the live-verification note.

### `v_patterns` is the whole contract for task 2.4

`v_patterns` projects exactly eight columns, and the pattern views consume all eight:

| Column | Type | Used for |
|---|---|---|
| `user_id` | uuid | repository-scoped read only — never a query parameter |
| `symbol` | text | `PatternDimension.symbol` |
| `session` | text (nullable) | `PatternDimension.session`; null groups as "Untagged" |
| `dow` | numeric | `PatternDimension.dayOfWeek` (0 = Sunday) |
| `hour` | numeric | `PatternDimension.hour` |
| `pnl` | numeric | net result of the group (`sum`), already cost-inclusive |
| `n` | bigint | sample size of the group (`count`) |
| `win_rate` | numeric | mean 0/1 flag, a 0…1 **fraction** |

**Not projected, and therefore deliberately not shown by the pattern views:** `r_multiple`,
`commission`, `swap`, `grade`, `setup`, `direction`. Those stay with `TradeMetrics` /
`TradeReview` (2.3). Adding `setup` to the group-by is the change that would unlock the
roadmap's "setup leaks"; it needs a view revision first, not a client-side roll-up.

## 6. Edge Functions

| Function | Trigger | Purpose |
|---|---|---|
| `meta-connect` | HTTP (auth) | register MetaAPI account, return id |
| `guard-check` | cron 1/min (pg_cron, migration 0004) | snapshot equity, compute guard, push 70/90, prune >30d |
| `sync-trades` | cron 5/min (pg_cron, migration 0005) | pull deals → upsert trades on `(account_id, external_id)`, advance `trade_sync_cursors` |
| `ai-review` | HTTP (auth) | OpenAI trade review JSON |
| `market-bars` | HTTP (auth) | TwelveData OHLC → normalise → upsert `prices_cache` (task 2.6) |
| `ai-analyze-chart` | HTTP (auth) | OpenAI vision → plan JSON |
| `copy-signal` | HTTP (auth) | lots calc → MetaAPI order (paper/live) |
| `purge-account` | HTTP (auth) | delete user data for Account Deletion |

`guard-check` is invoked by pg_cron + pg_net presenting the **service-role** key as a bearer token
(`supabase/config.toml` keeps `verify_jwt = true`, and the function re-checks the key itself, so a
guessed URL cannot make us spend MetaAPI allowance). Bring-up: `docs/BACKEND_DEPLOY.md`.

### Snapshot retention

`equity_snapshots` gains one row per account per minute — ~525k rows per account per year. `guard-check`
deletes rows older than **30 days** once a day (03:00 UTC), which is what the
`idx_equity_snapshots_created` index exists for. Anything longer than 30 days of minute-level equity
is not something the app charts.

## 7. API Contracts (app → edge)

```
POST /functions/v1/meta-connect       {login, password, server, platform} -> {metaapi_account_id}
GET  /functions/v1/guard-status?account_id= -> {daily_used_pct, daily_left, dd_distance,
                                                target_left_pct, equity, state, as_of}
POST /functions/v1/sync-trades        {account_id} -> {imported, updated}
POST /functions/v1/ai-review          {trade_id} -> {summary, leak, score, suggestions[]}
POST /functions/v1/market-bars          {symbol, interval} -> {symbol, interval, bars[], as_of}
POST /functions/v1/ai-analyze-chart   {image_url} -> {bias, levels[], entry, sl, tp[]}
POST /functions/v1/copy-signal        {signal_id, account_ids[], risk_pct, mode} -> {results[]}
```

Every contract has a matching mock in `lib/core/services/mock_*`.

## 8. Purging & Retention

`purge-account` deletes trades, snapshots, follows, reviews, storage screenshots and broker
tokens; anonymizes profile (email hashed) for purchase/tax records. SLA 30 days.

`prices_cache` is **not** per-user data and is deliberately not purged with an account: it holds
public OHLC candles keyed by symbol, holds nothing about the trader who fetched it, and is shared by
every user. Deleting it on account closure would discard a cache another trader's replay is reading.
The cache is pruned by age (rows nothing has requested for days), not by owner.
