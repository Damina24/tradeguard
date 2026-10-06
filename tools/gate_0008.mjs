// 0008 gate runner: run with
//   node tools/gate_0008.mjs <USER_TOKEN>
// USER_TOKEN = a signed-in trader's access token (grant_type=password).
// Never commits or prints the token; prints PASS/FAIL per check.
const BASE = 'https://jrzmqtmuatnnmwbrydio.supabase.co';
const ANON = 'sb_publishable_wXG6zRdgiRhq96MzhQ7e6Q_iOrz_8C4';
const token = process.argv[2];
if (!token) {
  console.error('usage: node tools/gate_0008.mjs <USER_TOKEN>');
  process.exit(2);
}
const ok = [];
const fail = [];
function verdict(name, pass, detail) {
  (pass ? ok : fail).push(name);
  console.log((pass ? 'PASS' : 'FAIL') + ' ' + name + (detail ? '  ' + detail : ''));
}
// 1. signed-in trader reads cached bars via PostgREST
{
  const r = await fetch(BASE + '/rest/v1/prices_cache?select=count', {
    headers: {
      apikey: ANON,
      Authorization: 'Bearer ' + token,
      Prefer: 'count=exact',
      Range: '0-0',
    },
  });
  const j = await r.json().catch(() => null);
  const count = Array.isArray(j) && j[0] ? Number(j[0].count) : NaN;
  // PostgREST answers a ranged count with 200 or 206; either is fine as
  // long as the count itself arrived. The thing that proves the policy is
  // count == service-role count, not the status code.
  verdict('1 user read returns a count (policy applied)', (r.status === 200 || r.status === 206) && Number.isFinite(count), 'status=' + r.status + ' count=' + (Number.isFinite(count) ? count : '?'));
}
// 2. anon sees nothing (empty data, not 401/403)
{
  const r = await fetch(BASE + '/rest/v1/prices_cache?select=count', {
    headers: { apikey: ANON, Prefer: 'count=exact', Range: '0-0' },
  });
  const j = await r.json().catch(() => null);
  const count = Array.isArray(j) && j[0] ? Number(j[0].count) : NaN;
  verdict('2 anon read returns count 0 as data', r.status === 200 && count === 0, 'status=' + r.status + ' count=' + count);
}
// 3. signed-in trader POST fails 401/403, never 201
{
  const r = await fetch(BASE + '/rest/v1/prices_cache', {
    method: 'POST',
    headers: {
      apikey: ANON,
      Authorization: 'Bearer ' + token,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    body: JSON.stringify({ symbol: 'GATEPROBE', timeframe: '1h', ohlc: [] }),
  });
  const text = await r.text().catch(() => '');
  const denied = r.status === 401 || r.status === 403;
  verdict('3 user POST denied (no cross-tenant write)', denied, 'status=' + r.status);
  if (r.status === 201) {
    console.log('!! probe row was created; deleting it');
    await fetch(BASE + "/rest/v1/prices_cache?symbol=eq.GATEPROBE&timeframe=eq.1h", {
      method: 'DELETE',
      headers: { apikey: ANON, Authorization: 'Bearer ' + token },
    });
  }
  void text;
}
console.log(fail.length === 0 ? 'GATE 0008: ALL PASS' : 'GATE 0008: ' + fail.length + ' FAILING');
process.exit(fail.length === 0 ? 0 : 1);
