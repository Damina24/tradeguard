// ai-analyze-chart — OpenAI vision analysis of a chart screenshot.
// TODO(Phase 3): fetch the Storage image, call the vision model, return a plan.
// Input: { image_url }  Output: { bias, levels[], entry, sl, tp[] }
Deno.serve(async (_req: Request): Promise<Response> => {
  return new Response(
    JSON.stringify({
      bias: 'neutral',
      levels: [] as number[],
      entry: 0,
      sl: 0,
      tp: [] as number[],
      stubbed: true,
    }),
    { headers: { 'Content-Type': 'application/json' } },
  );
});
