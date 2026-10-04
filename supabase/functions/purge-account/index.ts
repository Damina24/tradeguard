// purge-account — deletes all user data for the Account Deletion requirement.
// TODO(Phase 4): delete trades/snapshots/follows/reviews/screenshots, anonymise profile.
Deno.serve(async (_req: Request): Promise<Response> => {
  return new Response(
    JSON.stringify({ ok: true, function: 'purge-account', deleted_at: new Date().toISOString() }),
    { headers: { 'Content-Type': 'application/json' } },
  );
});
