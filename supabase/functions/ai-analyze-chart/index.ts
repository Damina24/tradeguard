// ai-analyze-chart — OpenAI vision analysis of a chart screenshot.
//
//   POST /functions/v1/ai-analyze-chart  {image_url} -> {bias, levels[]}
//
// All policy lives in `./shared.ts` so the test can verify it without a
// runtime, without `OPENAI_API_KEY` and without a Supabase project. This
// file adds only I/O.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
  ANALYSIS_MODEL,
  PROMPT_VERSION,
  buildPrompt,
  isOwnImagePath,
  mimeForPath,
  normaliseAnalysis,
  parseModelJson,
} from './shared.ts';

const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';
const STORAGE_BUCKET = 'chart-uploads';

type AnyRecord = Record<string, unknown>;

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function serviceClient(): any {
  const key = Deno.env.get('SUPABASE_SERVICE_KEY');
  const url = Deno.env.get('SUPABASE_URL');
  if (!key || !url) throw new Error('missing service credentials');

async function callerId(authHeader: string | null): Promise<string | null> {
  if (!authHeader || !authHeader.startsWith('Bearer ')) return null;
  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!url || !anonKey) return null;
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await userClient.auth.getUser();
  if (error) return null;
  const id = data?.user?.id;
  return typeof id === 'string' && id.length > 0 ? id : null;
}

async function askModel(prompt: { system: string; user: string }): Promise<
  { content: string } | { failure: string }
> {
  const key = Deno.env.get('OPENAI_API_KEY');
  if (!key) return { failure: 'notConfigured' };
  let res: Response;
  try {
    res = await fetch(OPENAI_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        model: ANALYSIS_MODEL,
        temperature: 0.2,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: prompt.system },
          { role: 'user', content: prompt.user },
        ],
      }),
    });
  } catch {
    return { failure: 'network' };
  }
  if (!res.ok) return { failure: 'server' };
  let body: unknown;
  try {
    body = await res.json();
  } catch {
    return { failure: 'malformed' };
  }
  const content = (body as AnyRecord)?.choices?.[0]?.message?.content;
  if (typeof content !== 'string') return { failure: 'malformed' };
  return { content };
}

  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}


Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return json({ ok: false, error: 'Method not allowed' }, 405);
  }
  const userId = await callerId(req.headers.get('Authorization'));
  if (userId === null) return json({ ok: false, error: 'Unauthorized' }, 401);
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'Invalid body' }, 400);
  }
  const imageUrl =
    typeof (body as AnyRecord)?.image_url === 'string'
      ? ((body as AnyRecord).image_url as string)
      : '';
  if (imageUrl.length === 0 || imageUrl.startsWith('http')) {
    return json({ ok: false, error: 'image_url must be a path' }, 400);
  }
  if (!isOwnImagePath(imageUrl, userId)) {
    return json({ ok: false, error: 'Forbidden' }, 403);
  }
  const mime = mimeForPath(imageUrl);
  if (mime === null) {
    return json({ ok: false, error: 'Unsupported image type' }, 400);
  }
  let sb: any;
  try {
    sb = serviceClient();
  } catch {
    return json({ ok: false, error: 'notConfigured' }, 503);
  }
  const { data, error } = await sb.storage
    .from(STORAGE_BUCKET)
    .download(imageUrl);
  if (error || !data) return json({ ok: false, error: 'server' }, 500);
  const buffer = await (data as Blob).arrayBuffer();
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  const dataUrl = `data:${mime};base64,${btoa(binary)}`;
  const prompt = buildPrompt();
  const answer = await askModel({
    system: prompt.system,
    user: `${prompt.user}\n\n![chart](${dataUrl})`,
  });
  if ('failure' in answer) {
    const status = answer.failure === 'notConfigured' ? 503 : 502;
    return json({ ok: false, error: answer.failure }, status);
  }
  const analysis = normaliseAnalysis(parseModelJson(answer.content));
  if (analysis === null) {
    return json({ ok: false, error: 'malformed' }, 502);
  }
  try {
    await sb.storage.from(STORAGE_BUCKET).remove([imageUrl]);
  } catch {
    // Non-fatal: the analysis is already produced.
  }
  return json({
    ok: true,
    bias: analysis.bias,
    levels: analysis.levels,
    entry: analysis.entry,
    sl: analysis.sl,
    tp: analysis.tp,
    note: analysis.note,
    model: ANALYSIS_MODEL,
    prompt_version: PROMPT_VERSION,
  });
});
