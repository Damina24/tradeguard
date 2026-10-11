// meta-connect — registers a broker account with MetaAPI and returns the opaque account id.
//
//   POST /functions/v1/meta-connect  {login, password, server, platform} -> {metaapi_account_id}
//
// Security contract (this is the whole point of the function):
//   * The broker password is forwarded to MetaAPI and NEVER written to Postgres, to a log line, or
//     returned to the caller. TradeGuard persists only `metaapi_account_id` (migration 0001).
//   * Requires a signed-in user (Authorization: Bearer <user JWT>) so one trader cannot register
//     accounts against another trader's allowance.
//   * Error responses are generic on purpose — a MetaAPI message can echo the login back.
//
// Secrets (`supabase secrets set ...`):
//   METAAPI_TOKEN  required
//
// Not covered by `flutter test`: it needs a deployed Supabase project plus a MetaAPI token. The
// pure `normalizePlatform` / `validateBody` helpers below are unit testable on their own.

const METAAPI_BASE = 'https://mt-provisioning-api-v1.agiliumtrade.agiliumtrade.ai';

const SUPPORTED_PLATFORMS = ['mt4', 'mt5', 'ctrader'] as const;

/** MetaAPI accepts only these platform strings; anything else is rejected before we spend a call. */
export function normalizePlatform(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const p = value.trim().toLowerCase();
  return (SUPPORTED_PLATFORMS as readonly string[]).includes(p) ? p : null;
}

export interface ConnectBody {
  login: string;
  password: string;
  server: string;
  platform: string;
}

/** Returns the cleaned body, or an error string the caller should surface verbatim. */
export function validateBody(
  raw: unknown,
): { ok: true; body: ConnectBody } | { ok: false; error: string } {
  if (typeof raw !== 'object' || raw === null) {
    return { ok: false, error: 'Expected a JSON body.' };
  }
  const r = raw as Record<string, unknown>;

  const login = typeof r.login === 'string' ? r.login.trim() : '';
  const password = typeof r.password === 'string' ? r.password : '';
  const server = typeof r.server === 'string' ? r.server.trim() : '';
  const platform = normalizePlatform(r.platform);

  // Mirrors `validateConnection` on the client — the same rules, enforced on both sides.
  if (!/^\d+$/.test(login)) {
    return { ok: false, error: 'Account number must be digits only.' };
  }
  if (password.length === 0) {
    return { ok: false, error: 'Password is required.' };
  }
  if (server.length === 0) {
    return { ok: false, error: 'Broker server is required.' };
  }
  if (platform === null) {
    return { ok: false, error: 'Unsupported platform.' };
  }

  return { ok: true, body: { login, password, server, platform } };
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
    },
  });
}

/** A random 32-hex-char id. MetaAPI requires a unique `transaction-id` per create request. */
function newTransactionId(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return json({}, 204);
  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed' }, 405);

  const token = Deno.env.get('METAAPI_TOKEN');
  if (!token) {
    // Config problem, not a user problem — say so plainly, but never echo the request body.
    return json({ ok: false, error: 'Broker connect is not configured.' }, 503);
  }

  // A signed-in user is required: this call spends the MetaAPI allowance on our account, so it
  // must not be usable anonymously.
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) {
    return json({ ok: false, error: 'Sign in to connect a broker account.' }, 401);
  }

  let parsed: unknown;
  try {
    parsed = await req.json();
  } catch {
    return json({ ok: false, error: 'Expected a JSON body.' }, 400);
  }

  const validated = validateBody(parsed);
  if (!validated.ok) return json({ ok: false, error: validated.error }, 400);

  const { login, password, server, platform } = validated.body;

  const transactionId = newTransactionId();
  const createBody = JSON.stringify({
    login,
    // MetaAPI requires a human-readable name; the broker login is a safe, unique label.
    name: `TradeGuard-${login}`,
    password,
    server,
    platform,
    type: 'cloud',
    // MetaAPI validates this endpoint and currently requires `magic` (the EA magic number that
    // identifies orders opened by the app). A fixed default is fine — TradeGuard only reads.
    magic: 123456,
  });

  // MetaAPI may answer 202 Accepted while it starts the cloud API server. The docs say to
  // re-send the identical request (same transaction-id) to poll for the eventual result.
  const postAccount = () =>
    fetch(`${METAAPI_BASE}/users/current/accounts`, {
      method: 'POST',
      headers: {
        'auth-token': token,
        'transaction-id': transactionId,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: createBody,
    });

  try {
    let res = await postAccount();
    for (let attempt = 0; res.status === 202 && attempt < 10; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 1500));
      res = await postAccount();
    }

    if (!res.ok) {
      console.error('meta-connect: MetaAPI rejected', res.status);
      const bodyText = await res.text();
      // Server-side only: the MetaAPI error body can echo the login back, so it is logged here for
      // debugging but NEVER returned to the caller (see the generic response below).
      console.error('MetaAPI Error Body:', bodyText);
      return json({ ok: false, error: 'The broker rejected those details.' }, 400);
    }

    const data = (await res.json()) as Record<string, unknown>;
    const accountId = data.id;
    if (typeof accountId !== 'string' || accountId.length === 0) {
      console.error('meta-connect: MetaAPI returned no id');
      return json({ ok: false, error: 'Broker connect returned an unexpected response.' }, 502);
    }

    // `password` is dropped here by simply never being referenced again — it is not stored.
    return json({ ok: true, metaapi_account_id: accountId });
  } catch (err) {
    console.error('meta-connect: unreachable', String(err));
    return json({ ok: false, error: 'Could not reach the broker connect service.' }, 502);
  }
});
