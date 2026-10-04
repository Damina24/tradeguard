-- TradeGuard Phase 1 — actually schedule `guard-check`, and stop `equity_snapshots` growing without
-- bound.
--
-- Why this migration exists: `docs/BACKEND_SCHEMA.md` gives `guard-check` (cron 1/min) ownership of
-- the equity snapshot and the 70/90 push, but nothing was invoking it, so the Guard screen could
-- never leave STALE in a real deployment. pg_cron + pg_net (both available on hosted Supabase) is
-- the supported way to schedule an Edge Function without running an external scheduler.
--
-- The service-role key is read from Vault *at run time*, never interpolated into `cron.job.command`
-- — `cron.job` is readable by anything that can query it, so a literal key there would leak.

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- 1. Retention index. The delete below filters on `created_at` alone, and the existing index is
--    keyed on (account_id, created_at) so it cannot serve that on its own.
create index if not exists idx_equity_snapshots_created
  on equity_snapshots (created_at);

-- 2. Make the migration re-runnable: drop any previous schedule first, otherwise re-applying it
--    leaves a duplicate job that double-pushes every alert.
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'guard-check-minutely';
exception
  -- Nothing scheduled yet (or pg_cron is unavailable on this instance): nothing to clean up.
  when undefined_table or invalid_schema_name then null;
end $$;

-- 3. The schedule itself. Requires these Vault entries — see `docs/BACKEND_DEPLOY.md`:
--      project_url          = https://<project-ref>.supabase.co
--      service_role_key     = the service_role key
--    Until they exist the job fails with a NULL url and the guard simply stays stale, which is a
--    visible, safe failure rather than a silently wrong one.
select cron.schedule(
  'guard-check-minutely',
  '* * * * *',
  $$
  select net.http_post(
    url := (
      select decrypted_secret from vault.decrypted_secrets where name = 'project_url'
    ) || '/functions/v1/guard-check',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'
      )
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 50000
  );
  $$
);

-- `sync-trades` (Phase 2, task 2.2) gets the same treatment when that function is implemented;
-- until then there is deliberately no job pointing at a stub that would 404 every five minutes.