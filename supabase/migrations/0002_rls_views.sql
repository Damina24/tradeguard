-- TradeGuard indexes, views, RLS (Phase 0)

create index if not exists trades_account_close_idx on trades (account_id, close_time desc);
create index if not exists snapshots_account_created_idx on equity_snapshots (account_id, created_at desc);
create index if not exists signals_status_created_idx on signals (status, created_at desc);
create index if not exists follows_user_created_idx on signal_follows (user_id, created_at desc);

create or replace view v_daily_pnl as
select account_id,
       date_trunc('day', close_time) as day,
       sum(pnl) as pnl,
       count(*) as trades
from trades
group by 1, 2;

create or replace view v_patterns as
select user_id, symbol, session,
       extract(dow from close_time) as dow,
       extract(hour from close_time) as hour,
       sum(pnl) as pnl,
       count(*) as n,
       avg(case when pnl > 0 then 1 else 0 end) as win_rate
from trades
group by 1, 2, 3, 4, 5;

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

create policy "own snapshots" on equity_snapshots
  for select using (
    exists (
      select 1 from broker_accounts a
      where a.id = equity_snapshots.account_id and a.user_id = auth.uid()
    )
  );

create policy "signals read" on signals
  for select using (auth.role() = 'authenticated');

-- Auto-create a profile row when a user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
