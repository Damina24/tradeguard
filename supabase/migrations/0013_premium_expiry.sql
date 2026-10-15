-- Premium expiry (0013).
--
-- Closes the "lifetime access" loophole from migration 0012: `is_premium`
-- alone never expires, so a single $15 monthly payment unlocked Pro forever.
-- This migration adds `premium_expires_at TIMESTAMPTZ` (NULL = lifetime /
-- legacy grant, non-NULL = subscription expiry). The app's premium check is
-- now `is_premium = true AND (premium_expires_at IS NULL OR
-- premium_expires_at > NOW())`; the `flutterwave-webhook` Edge Function sets
-- both columns from `data.amount` (see supabase/functions/flutterwave-webhook).
--
-- RLS is unchanged: the read-only `read own profile` policy from 0012 still
-- governs this table. No new policy, no auth-flow change. The service-role
-- webhook remains the only writer.

alter table profiles
  add column if not exists premium_expires_at timestamptz;

-- Fast "who is currently premium?" lookup without touching RLS semantics.
create index if not exists profiles_premium_expiry_idx
  on profiles (is_premium, premium_expires_at)
  where is_premium = true;
