-- TradeGuard initial schema (Phase 0)
-- Mirrors docs/BACKEND_SCHEMA.md

create extension if not exists "pgcrypto";

create table if not exists profiles (
  id uuid primary key references auth.users on delete cascade,
  email text,
  plan text not null default 'free',
  rc_customer_id text,
  onboarded boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists broker_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  platform text not null,
  metaapi_account_id text,
  nickname text not null,
  prop_firm text,
  phase text not null default 'eval',
  currency text not null default 'USD',
  initial_balance numeric not null default 0,
  profit_target numeric,
  daily_loss_limit numeric,
  max_drawdown numeric,
  drawdown_type text not null default 'static',
  equity_guard_enabled boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists trades (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  account_id uuid not null references broker_accounts(id) on delete cascade,
  external_id text,
  symbol text not null,
  direction text not null,
  lots numeric not null,
  entry numeric, exit numeric, sl numeric, tp numeric,
  open_time timestamptz, close_time timestamptz,
  pnl numeric not null default 0,
  commission numeric not null default 0,
  swap numeric not null default 0,
  mfe numeric, mae numeric,
  setup text, session text,
  grade text,
  notes text, screenshot_url text,
  created_at timestamptz not null default now(),
  unique (user_id, external_id)
);

create table if not exists equity_snapshots (
  id bigserial primary key,
  account_id uuid not null references broker_accounts(id) on delete cascade,
  equity numeric not null, balance numeric not null,
  drawdown_used numeric not null default 0,
  daily_pnl numeric not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists signals (
  id uuid primary key default gen_random_uuid(),
  pair text not null, direction text not null,
  entry numeric, sl numeric, tp1 numeric, tp2 numeric, tp3 numeric,
  confidence int, rationale text,
  status text not null default 'active',
  result_pips numeric,
  premium boolean not null default false,
  posted_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists signal_follows (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  signal_id uuid not null references signals(id) on delete cascade,
  account_id uuid not null references broker_accounts(id) on delete cascade,
  lots numeric, risk_pct numeric,
  mode text not null default 'paper',
  copy_status text not null default 'pending',
  pnl numeric default 0,
  created_at timestamptz not null default now()
);

create table if not exists ai_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  trade_id uuid references trades(id) on delete cascade,
  summary text, leak text, score int, suggestions jsonb,
  model text, created_at timestamptz not null default now()
);

create table if not exists prices_cache (
  symbol text not null, timeframe text not null,
  ohlc jsonb not null, updated_at timestamptz not null default now(),
  primary key (symbol, timeframe)
);
