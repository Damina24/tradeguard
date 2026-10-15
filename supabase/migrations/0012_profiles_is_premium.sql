-- Flutterwave premium toggle (0012).
--
-- The whole "is this trader premium?" state is a single boolean on `profiles`.
-- There is no subscription table and no store SDK: the app opens a Flutterwave
-- Payment Link in the browser, Flutterwave calls the `flutterwave-webhook` Edge
-- Function on `charge.completed` (or `subscription.created`), and that function
-- flag to true. The client only ever READS it.
--
-- RLS is tightened to read-only for the signed-in user. The base policy from
-- migration 0002 was `for all`, which would let a user UPDATE their own
-- `is_premium` to true from the client and unlock premium for free. No client
-- code writes `profiles` (verified: the only writers are the `handle_new_user`
-- signup trigger, which is `security definer` and bypasses RLS, and the
-- service-role webhook), so a `for select`-only policy is both sufficient and
-- the safest option.

alter table profiles
  add column if not exists is_premium boolean not null default false;

-- Replace the permissive `for all` policy with a read-only, own-row policy.
drop policy if exists "own profile" on profiles;

create policy "read own profile" on profiles
  for select using (auth.uid() = id);
