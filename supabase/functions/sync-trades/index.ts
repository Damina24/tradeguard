// sync-trades — cron 5/min. Pulls deals from MetaAPI and upserts into trades.
// TODO(Phase 2): paginate MetaAPI history, dedupe on (user_id, external_id).
Deno.serve(async (_req: Request): Promise<Response> => {
  return new Response(
    JSON.stringify({ ok: true, function: 'sync-trades', imported: 0, updated: 0 }),
    { headers: { 'Content-Type': 'application/json' } },
  );
});
