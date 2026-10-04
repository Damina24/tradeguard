// copy-signal — computes risk-based lots and (optionally) places orders via MetaAPI.
// PAPER MODE by default. Live orders require an explicit consent flag from the client.
// Input: { signal_id, account_ids[], risk_pct, mode: 'paper'|'live' }
Deno.serve(async (_req: Request): Promise<Response> => {
  return new Response(
    JSON.stringify({
      results: [] as unknown[],
      mode: 'paper',
      stubbed: true,
    }),
    { headers: { 'Content-Type': 'application/json' } },
  );
});
