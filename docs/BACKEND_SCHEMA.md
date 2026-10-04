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
  pnl numeric default 0,
  created_at timestamptz not null default now()
);

create table ai_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  trade_id uuid references trades(id) on delete cascade,
  summary text, leak text, score int, suggestions jsonb,
  model text, created_at timestamptz not null default now()
);

create table prices_cache (

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

create policy "own profile" on profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

create policy "own accounts" on broker_accounts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own trades" on trades
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own follows" on signal_follows
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

## 6. Edge Functions

| Function | Trigger | Purpose |
|---|---|---|
| `meta-connect` | HTTP (auth) | register MetaAPI account, return id |
| `guard-check` | cron 1/min | snapshot equity, compute guard, push 70/90 |
| `sync-trades` | cron 5/min | pull deals → upsert trades |
| `ai-review` | HTTP (auth) | OpenAI trade review JSON |
| `ai-analyze-chart` | HTTP (auth) | OpenAI vision → plan JSON |
| `copy-signal` | HTTP (auth) | lots calc → MetaAPI order (paper/live) |
| `purge-account` | HTTP (auth) | delete user data for Account Deletion |

## 7. API Contracts (app → edge)

```
POST /functions/v1/meta-connect       {login, password, server, platform} -> {metaapi_account_id}
GET  /functions/v1/guard-status?account_id= -> {daily_used_pct, daily_left, dd_distance,
                                                target_left_pct, equity, state, as_of}
POST /functions/v1/sync-trades        {account_id} -> {imported, updated}
POST /functions/v1/ai-review          {trade_id} -> {summary, leak, score, suggestions[]}
POST /functions/v1/ai-analyze-chart   {image_url} -> {bias, levels[], entry, sl, tp[]}
POST /functions/v1/copy-signal        {signal_id, account_ids[], risk_pct, mode} -> {results[]}
```

Every contract has a matching mock in `lib/core/services/mock_*`.

## 8. Purging & Retention

`purge-account` deletes trades, snapshots, follows, reviews, storage screenshots and broker
tokens; anonymizes profile (email hashed) for purchase/tax records. SLA 30 days.

  symbol text not null, timeframe text not null,
  ohlc jsonb not null, updated_at timestamptz not null default now(),
  primary key (symbol, timeframe)
);
```
