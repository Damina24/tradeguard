-- TradeGuard Phase 2 — trade screenshot storage (task 2.3).
--
-- `trades.screenshot_url` has existed since migration 0001 and `Trade.screenshotUrl` is already read
-- by the client, but no migration ever created the bucket that backs it — the roadmap's remaining
-- tracked item ("screenshot upload still ⬜", IMPLEMENTATION_PLAN.md task 2.3). This migration adds
-- exactly the storage backing and nothing else: the upload/link/display flow lives in
-- `lib/features/journal/data/trade_screenshot_service.dart` + the Trade Detail screen.
--
-- ── Design ─────────────────────────────────────────────────────────────────────────────────────
--   * Private bucket `trade-screenshots` (public = false). Screenshots are per-trader journal data,
--     not public market facts like `prices_cache` (migration 0008, deliberately world-readable).
--   * Object path convention: `<owner-uid>/<trade-id>/<millis>.<ext>`. The first path segment is the
--     owner's `auth.uid()`, which is what the policies key on — the same ownership model as the
--     `own trades` RLS policy on the `trades` table (migration 0002).
--   * `trades.screenshot_url` stores the STORAGE PATH, not a URL. The bucket is private, so a stored
--     https URL would either leak (public bucket) or rot (signed URL with an expiry). The client
--     downloads bytes with its own authenticated session (`storage.from(...).download(path)`), which
--     is what the SELECT policy below authorises.
--   * Size/type enforcement is client-side (`TradeScreenshotService`: 5 MB, JPEG/PNG/WebP). The row
--     insert here only names the bucket; file_size_limit / allowed_mime_types are intentionally NOT
--     set in SQL because the `storage.buckets` column set differs across self-hosted versions and a
--     version-specific column list would break `supabase db push` elsewhere.
--
-- ── What is deliberately NOT here ──────────────────────────────────────────────────────────────
--   * No public read: anyone with a public-bucket URL could enumerate a trader's journal images.
--   * No `trades.screenshot_url` foreign key to `storage.objects`: the two live in different schemas
--     with different lifecycles, and `purge-account` deletes them in one pass anyway.
--   * No Phase 3 (copy-trading) changes.

-- 1. Column (idempotent — 0001 already created it, this is the re-run/backfill guard).
alter table trades add column if not exists screenshot_url text;

comment on column trades.screenshot_url is
  'Storage path of the trade screenshot in the trade-screenshots bucket '
  '(<owner-uid>/<trade-id>/<millis>.<ext>), never a public or signed URL. '
  'Written by TradeScreenshotService upload + TradeRepository.updateScreenshot.';

-- 2. Private bucket.
insert into storage.buckets (id, name, public)
values ('trade-screenshots', 'trade-screenshots', false)
on conflict (id) do nothing;

-- 3. Owner-scoped access. First path segment must equal the caller's uid, so a trader can only
-- touch their own prefix. RLS is already enabled on storage.objects by the platform; these are the
-- only policies for this bucket, so anything not matching is denied.
drop policy if exists "trade screenshots owner read" on storage.objects;
create policy "trade screenshots owner read" on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'trade-screenshots'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "trade screenshots owner write" on storage.objects;
create policy "trade screenshots owner write" on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'trade-screenshots'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "trade screenshots owner update" on storage.objects;
create policy "trade screenshots owner update" on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'trade-screenshots'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'trade-screenshots'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "trade screenshots owner delete" on storage.objects;
create policy "trade screenshots owner delete" on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'trade-screenshots'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- ---------------------------------------------------------------------------------------------
-- Verification notes
-- ---------------------------------------------------------------------------------------------
-- NOT executed against a live Supabase project in this environment (no linked project here), so
-- verify after `supabase db push` through POSTGREST, NOT the SQL Editor (postgres bypasses RLS):
--
--   1. As trader A: upload `<uid-A>/t1/1.jpg` via the authenticated storage API succeeds.
--   2. As trader A: downloading that object succeeds; as trader B it fails (404/403) — the
--      cross-tenant read this migration closes.
--   3. Anon (no JWT) upload/download fails.
--   4. `trades.screenshot_url` for A's trade reads back the stored path; B sees 0 rows for it
--      through the existing `own trades` policy.
--
-- Re-running `supabase db push` is safe: the ALTER is `if not exists`, the bucket insert is
-- `on conflict do nothing`, and every policy is dropped first.
