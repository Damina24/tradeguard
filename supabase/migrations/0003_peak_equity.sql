-- TradeGuard Phase 1 — trailing drawdown needs a running peak, and the app reads the newest
-- snapshot per account on every Guard refresh.
--
-- 1. equity_snapshots had no peak_equity column, so a trailing-drawdown prop account could never
--    be evaluated correctly: TradingMath.drawdownDistance needs peak equity. Backfill from the
--    highest equity ever recorded so existing history is not silently reset to zero.
-- 2. "newest snapshot per account" was a full scan plus a client-side dedupe. This index turns it
--    into a bounded index scan, which matters because the Guard screen polls it.

alter table equity_snapshots
  add column if not exists peak_equity numeric not null default 0;

update equity_snapshots s
set peak_equity = coalesce(h.max_equity, s.equity)
from (
  select account_id, max(equity) as max_equity
  from equity_snapshots
  group by account_id
) h
where s.account_id = h.account_id
  and s.peak_equity = 0;

create index if not exists idx_equity_snapshots_account_created
  on equity_snapshots (account_id, created_at desc);
