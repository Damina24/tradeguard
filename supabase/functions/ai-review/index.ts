// ai-review — OpenAI trade review. Key stays server-side.
// TODO(Phase 2): build prompt from trade fields, call gpt-4o-mini, store in ai_reviews.
// Input: { trade_id }  Output: { summary, leak, score, suggestions[] }
Deno.serve(async (_req: Request): Promise<Response> => {
  return new Response(
    JSON.stringify({
      summary: 'Stubbed review — configure OPENAI_API_KEY to enable.',
      leak: 'No data yet.',
      score: 0,
      suggestions: [] as string[],
      model: 'gpt-4o-mini',
      stubbed: true,
    }),
    { headers: { 'Content-Type': 'application/json' } },
  );
});
