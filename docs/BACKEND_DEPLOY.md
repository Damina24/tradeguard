# BACKEND_DEPLOY.md — taking TradeGuard off mock mode 🧑

Everything here needs credentials only you can create, which is why the app boots in **mock mode**
with seeded demo data. Work top to bottom; each step is verifiable on its own.

Order matters: the schema must exist before functions can talk to it, and the Vault secrets must
exist before the cron job can fire.

---

## 0. Prerequisites

```bash
npm i -g supabase          # or: scoop install supabase / brew install supabase
supabase login
```

Project → **Settings → API** → note `Project URL`, `anon public` key and `service_role` key.
`service_role` bypasses RLS: treat it like a database password and never commit it.

---

## 1. Create the project and link it

```bash
supabase projects create tradeguard --org-id <your-org-id> --db-password <strong-password>
supabase link --project-ref <project-ref>
```

---

## 2. Schema + the `guard-check` schedule

```bash
supabase db push
```

That applies `0001_init.sql` … `0010_trade_screenshots_storage.sql`. Migration 0009 is the copy-signal
schema (tasks 3.5/3.6): `broker_accounts.copy_enabled` (per-account permission, OFF by default),
`copy_settings` (live consent, kill switch, lot + concurrent caps, absent row == defaults), and
`signal_follows.order_id` (live rows always carry one, paper rows always NULL — enforced by the
`signal_follows_live_needs_order_id` check). It stores the facts the `copy-signal` policy reads
and duplicates no rule in SQL. The cron migrations need two Vault
secrets, so insert them **before** pushing them — or re-run them afterwards:

```sql
-- Dashboard → SQL Editor, or: psql "$DATABASE_URL"
select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
select vault.create_secret('<service_role key>', 'service_role_key');
```

Why Vault instead of a literal in the SQL: `cron.job.command` is a plain string in a table anyone
with SQL access can read. Reading the secret at run time keeps the key out of it. The jobs call
`guard-check` / `sync-trades` with `Authorization: Bearer <service_role>`, which is what both
functions now require.

`0005_sync_trades.sql` also **corrects the `trades` dedupe key** from `(user_id, external_id)`
to `(account_id, external_id)`. A broker deal id is unique per broker *account*, so with the old
key a trader holding two broker accounts would have had one account's sync overwrite the
other's rows. Read the comment at the top of the file before pushing it.

```sql
select jobname, schedule, active from cron.job
 where jobname in ('guard-check-minutely', 'sync-trades-5min');
```

### Fire it once by hand

```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/guard-check" \
  -H "Authorization: Bearer <service_role>" \
  -H "apikey: <service_role>" \
  -H "Content-Type: application/json" -d '{}'
# → {"ok":true,"at":"…","checked":2,"snapshots":2,"alerts":0,"skipped":0,"pruned":0}
```

Without the bearer you get `401 {"ok":false,"error":"Unauthorized"}` — that is the check working.
A minute later there should be one `equity_snapshots` row per active account.

---

## 3. Function secrets

```bash
supabase secrets set METAAPI_TOKEN=<metaapi-token>
supabase secrets set TWELVEDATA_KEY=<twelvedata-key>
supabase secrets set SUPABASE_SERVICE_KEY=<service_role>
supabase secrets set FIREBASE_SERVICE_ACCOUNT='{"type":"service_account","project_id":"…", …}'
```

| Secret | Needed for | If missing |
|---|---|---|
| `SUPABASE_SERVICE_KEY` | both cron workers | functions 500s |
| `METAAPI_TOKEN` | reading live equity + syncing trades | equity falls back to the last snapshot; no trade sync |
| `TWELVEDATA_KEY` | the `market-bars` price cache | the replay falls back to cached bars, then to `SYNTHETIC DEMO` |
| `FIREBASE_SERVICE_ACCOUNT` | the 70/90 push | numbers are stored, no notification |

`TWELVEDATA_KEY` is **server-side only** and must never be added to `env/dev.json`: a
`--dart-define` value ships inside the APK, where anyone who installs the app can extract it and spend
our metered allowance from outside the product. See the task 2.6 notes in
`docs/IMPLEMENTATION_PLAN.md`.

`FIREBASE_SERVICE_ACCOUNT` is the **whole** service-account JSON (Firebase console → Project settings
→ Service accounts → Generate new private key). Quoting matters: an unquoted value containing spaces
or `\n` breaks the secret.

```bash
supabase functions deploy guard-check sync-trades meta-connect
```

### Fire `sync-trades` once by hand

```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/sync-trades" \
  -H "Authorization: Bearer <service_role>" \
  -H "apikey: <service_role>" \
  -H "Content-Type: application/json" -d '{}'
# → {"ok":true,"at":"…","checked":1,"synced":1,"imported":12,"skipped":0,"failed":0}
```

Without the bearer you get `401 {"ok":false,"error":"Unauthorized"}` — that is the check working.
Run it twice: the second run must report `imported:0` and add no rows, because the upsert is keyed
on `(account_id, external_id)`. Check with:

```sql
select account_id, count(*) from trades group by 1;
select * from trade_sync_cursors;
```

To sync a single account by id, pass `{"account_id":"<uuid>"}`. The id must be one of your own
active accounts or the call returns `404` — it is never used to choose a write target.

Its policy lives in `supabase/functions/sync-trades/shared.ts` and is unit-tested without a
runtime:

```bash
node supabase/functions/sync-trades/sync-trades_test.ts
# → sync-trades: 41 tests passed
```

---

## 3a. The `market-bars` price cache (task 2.6)

```bash
supabase functions deploy market-bars
```

`market-bars` is **user-facing** (a trader opens the Replay screen), so it uses the `ai-review` gate —
`verify_jwt = true` plus a GoTrue lookup of the caller's own bearer — *not* the service-role gate the
two cron workers use. It needs `TWELVEDATA_KEY` and `SUPABASE_SERVICE_KEY`.

```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/market-bars" \
  -H "Authorization: Bearer <a user access token>" \
  -H "apikey: <anon key>" \
  -H "Content-Type: application/json" \
  -d '{"symbol":"XAUUSD","interval":"1h"}'
# → {"ok":true,"symbol":"XAUUSD","interval":"1h","bars":[…],"as_of":"…","cached":false}
```

Two behaviours worth checking explicitly, because both are deliberate:

- **Run it twice.** The second call must report `"cached":true` and make **no** upstream request —
  a fresh row is answered without touching the metered provider.
- **An off-list symbol is `404` before any network call**, and costs nothing:

```bash
-d '{"symbol":"TSLA","interval":"1h"}'   # → 404 {"ok":false,"error":"Unknown symbol"}
```

```sql
-- service-role / SQL Editor view of what exists
select symbol, timeframe, jsonb_array_length(ohlc) from prices_cache order by 1, 2;
```

### 🧑 Gate: verify migration 0008 before replay is called live

**This step is not optional. Task 2.6 is not "live" until all three checks below pass.**

Before 0008, `prices_cache` had RLS enabled and *no policy*, so every client read returned an
**empty set** rather than an error. That is the dangerous failure mode here: the replay renders
"no bars cached for this symbol" and the trader concludes the backend is broken, instead of being
told the read was denied. A check that only looks at row counts will not catch it.

> ⚠️ **Run these through PostgREST, not the SQL Editor.** In the SQL Editor you are `postgres`,
> which **bypasses RLS**: `select count(*)` would ignore the policy and the `insert` would
> *succeed*. That is a false green. Supabase's REST layer is what the app actually uses, so that is
> what must be tested. Set `USER_TOKEN` to a signed-in trader's access token (sign in through the
> app, or `POST /auth/v1/token?grant_type=password` with a real account).

**1. A signed-in trader can read cached bars** — expect a count **equal to** the row count from the
query above. A `0` here means the policy is missing or wrong, even though the rows exist:

```bash
curl "https://<project-ref>.supabase.co/rest/v1/select=count" \
  -H "apikey: <anon key>" -H "Authorization: Bearer <USER_TOKEN>" \
  -H "Prefer: count=exact" -H "Range: 0-0"
# ✅ → [{"count":"<N>"}]   N > 0 and N matches the service-role count
# ❌ → [{"count":"0"}]     rows exist but the policy is not applied
```

**2. `anon` sees nothing** — expect zero, returned as data rather than as a 401/403. RLS filters
silently, so an unauthenticated caller cannot enumerate the cache by primary key:

```bash
curl "https://<project-ref>.supabase.co/rest/v1/select=count" \
  -H "apikey: <anon key>" -H "Prefer: count=exact" -H "Range: 0-0"
# ✅ → [{"count":"0"}]
```

**3. No client may write the cache** — the cross-tenant poisoning route this migration closes.
Expect an auth failure, **never** `201 Created`:

```bash
curl -i -X POST "https://<project-ref>.supabase.co/rest/v1/prices_cache" \
  -H "apikey: <anon key>" -H "Authorization: Bearer <USER_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"symbol":"XAUUSD","timeframe":"1h","ohlc":[]}'
# ✅ → HTTP 401 or 403  ("new row violates row-level security policy" / permission denied)
# ❌ → HTTP 201        DELETE IT: delete from prices_cache where symbol='XAUUSD' and timeframe='1h';
```

Finally, confirm the objects actually landed (safe to run as `postgres` — this only inspects the
catalog, it does not exercise RLS):

```sql
select policyname, cmd, roles from pg_policies where tablename = 'prices_cache';
-- ✅ → "read cached bars" | SELECT | {authenticated}
select indexname from pg_indexes where tablename = 'prices_cache';
-- ✅ → prices_cache_pkey, prices_cache_updated_idx
```

Its policy lives in `supabase/functions/market-bars/shared.ts` and is unit-tested without a runtime:

```bash
node supabase/functions/market-bars/market-bars_test.ts
# → market-bars: 21 passed
```

---

## 3b. The `copy-signal` function (tasks 3.5/3.6)

```bash
supabase functions deploy copy-signal
```

`copy-signal` is **user-facing** (a trader taps Copy on a signal), so it uses the `ai-review`
gate — `verify_jwt = true` plus a GoTrue lookup of the caller's own bearer — *not* the
service-role gate the two cron workers use. It needs `SUPABASE_URL` / `SUPABASE_SERVICE_KEY` /
`SUPABASE_ANON_KEY` (platform-provided); `METAAPI_TOKEN` is required for LIVE mode only —
paper mode never touches MetaAPI, and a live request without the token fails `notConfigured`
(503) rather than being downgraded to paper.

Its policy lives in `supabase/functions/copy-signal/shared.ts` (`evaluateAccount`) and is
unit-tested without a runtime — this is the same suite CI runs:

```bash
node supabase/functions/copy-signal/copy_signal_test.ts
# → copy-signal: 23 tests passed
```

The Dart half of the contract (parity fixtures identical to the TS table, `CopySettings`
defaults, `CopyPreview` ladder) is covered by `flutter test` (`test/copy_policy_test.dart` +
`test/copy_confirm_sheet_test.dart`). A formula change that lands on one side only fails both
suites.

```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/copy-signal" \
  -H "Authorization: Bearer <a user access token>" \
  -H "apikey: <anon key>" \
  -H "Content-Type: application/json" \
  -d '{"signal_id":"<uuid>","account_ids":["<uuid>"],"risk_pct":1,"mode":"paper"}'
# → {"ok":true,"mode":"paper","results":[{"account_id":"…","mode":"paper","lots":1.33,…,"simulated":true}]}
```

Behaviours worth checking explicitly, because each is deliberate:

- **Paper is the default and live is never inferred.** Any `mode` other than the exact string
  `live` runs as paper; a `live` ask without stored `copy_settings.live_consent` is refused
  (`consentRequired`), never silently downgraded.
- **The kill switch blocks everything, paper included** (`killSwitch` refusal first in the order).
- **Per-account permission is OFF by default**: a freshly connected account refuses every follow
  (`accountDisabled`) until the trader enables copy for it.
- **Lots are recomputed server-side** from server-side equity (`equity_snapshots`, fallback
  `initial_balance`) with `risk_pct` clamped to 0.25–5.00%; over the cap is refused (`maxLots`),
  never silently clamped. No client-supplied size ever reaches a row or a broker.
- **Live rows always carry `order_id`** (paper rows always NULL — the `signal_follows_live_needs_order_id`
  check). A live order whose id came back null is reported `failed` and never inserted.
- **No master/slave routing exists**: each requested account is evaluated independently in
  request order, and an id that is not the caller's is `accountMissing` — identical to a
  nonexistent account, so the endpoint cannot probe for other traders' ids.

---

## 3c. The `delete-account` function (store compliance)

```bash
supabase functions deploy delete-account
```

`delete-account` powers the in-app **Delete Account** action both stores require (Apple
**5.1.1(v)**, Google Play account-deletion). It is **user-facing**, so it uses the same
`ai-review` gate as `copy-signal` — `verify_jwt = true` (`supabase/config.toml`) plus a GoTrue
lookup of the caller's **own** bearer token. The uid comes only from that verified JWT; there is
no request body and no id is ever read from a header other than the token. It needs
`SUPABASE_URL` / `SUPABASE_SERVICE_KEY` / `SUPABASE_ANON_KEY` (platform-provided) — no extra
secret.

What one call does, in order (all scoped to the caller's verified uid):

1. Deletes the caller's rows **child-first** in every table that holds a `user_id` column —
   enumerated from migrations 0001–0010 in `supabase/functions/delete-account/shared.ts`
   (`TABLES`): `ai_reviews`, `signal_follows`, `trade_sync_cursors`, `trades`, `broker_accounts`
   (whose delete cascades `equity_snapshots`), `copy_settings`, then `profiles` (keyed by `id`).
   Global tables — `signals` (`posted_by`) and `prices_cache` (no `user_id`) — are **never**
   touched.
2. Lists then removes the caller's objects in the private `trade-screenshots` bucket under the
   `<uid>/` path prefix (migration 0010).
3. Calls `supabase.auth.admin.deleteUser(uid)` **last**, so a mid-way failure leaves an intact,
   signed-in account the trader can retry — never an orphaned login with half its rows gone.

It is **idempotent**: a second call finds nothing to delete and still returns a success summary
(an already-deleted user from `deleteUser` is treated as success, not an error). Responses are
`401` (no/invalid bearer), `405` (non-POST), `503` (function not configured) or `500` (a delete
failed) with a safe token; the server logs **counts and short codes only**, never a body or a uid.

The orchestration and the whole contract are unit-tested without a runtime against a recording
fake client — this is the suite CI runs:

```bash
node supabase/functions/delete-account/delete_account_test.ts
# → delete-account: 14 tests passed
```

The Dart half (destructive two-step dialog, checkbox-gated confirm, sign-out on success,
trader-safe errors) is covered by `flutter test` (`test/delete_account_dialog_test.dart`).

```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/delete-account" \
  -H "Authorization: Bearer <a user access token>" \
  -H "apikey: <anon key>"
# → {"ok":true,"deleted":{"ai_reviews":2,"signal_follows":1,"trade_sync_cursors":1,"trades":42,
#     "broker_accounts":2,"copy_settings":1,"profiles":1},"storage":3,"user_deleted":true}
```

Without the bearer you get `401 {"ok":false,"error":"Unauthorized"}` — that is the auth gate
working. To verify end to end, sign in as a trader with data, run the call once (rows and
screenshots gone, user removed), then run it again — the second call returns the same success
shape with all counts `0`.

> Deleting the account does **not** cancel an active subscription. The dialog says so and points
> the trader to the App Store / Google Play subscription settings; cancellation is manual and out
> of band. See also `docs/ACCOUNT_DELETION.md` (the public data-deletion page the stores link to).

---

## 4. Apple & Google sign-in 🧑

The client is done (`sign_in_with_apple` / `google_sign_in` → `signInWithIdToken`). These steps make
the tokens verify:

**Supabase → Authentication → Providers**

| Provider | What to paste |
|---|---|
| Apple | Apple Developer → Keys, then App Store Connect → Keys. Set `APPLE_ID`, `TEAM_ID`, `KEY_ID` and the `p8` key. Turn on "Use nonce". |
| Google | Google Cloud console → OAuth consent screen (*Internal* while testing) → Credentials → **Web** client ID + secret. |

**Apple Developer (iOS)**

1. Enable the **Sign in with Apple** capability on App ID `com.tradeguard.app`.
2. Add a **Service ID** `com.tradeguard.app.web` for the Android/web flow, listing
   `https://<project-ref>.supabase.co/auth/v1/callback` as a return URL.
3. Its identifier reaches the app as `APPLE_WEB_CLIENT_ID` in `env/dev.json` (Android only).

**Google**

4. Create Android and iOS OAuth clients too — package `com.tradeguard.app` plus the release **and**
   debug SHA-1 fingerprints.
5. iOS: add the reversed client id to `Info.plist` as a `URL Type` (see `ios/SETUP_NOTES.md`).
6. Put the **Web** client id in `env/dev.json` as `GOOGLE_SERVER_CLIENT_ID` — the plugin needs it on
   Android to mint a token Supabase accepts — and the iOS one as `GOOGLE_IOS_CLIENT_ID`.

Without these the buttons still render and report *"… is not configured for this build"*; email and
password keep working.

---

## 5. Push notifications 🧑

1. Firebase console → add app `com.tradeguard.app` (Android) and iOS bundle `com.tradeguard.app`.
2. Download `google-services.json` / `GoogleService-Info.plist` into `android/app/` and `ios/Runner/`
   (both git-ignored).
3. Add the **Push Notifications** capability + APNs key in App Store Connect.
4. Deploy with `FIREBASE_SERVICE_ACCOUNT` set (step 3).

The client subscribes each device to `guard_<accountId>` (FCM topics only allow `[a-zA-Z0-9-_.~%]`);
`guard-check` publishes to the same name. Both derive it from the account id, so they cannot drift.

---

## 6. Run the app against it

```powershell
copy env\dev.example.json env\dev.json      # fill in every value; env\ is git-ignored
flutter run --dart-define-from-file=env/dev.json
```

With `SUPABASE_URL` set, `AppConfig.useMock` flips to false: real auth, real accounts, and the Guard
screen reads the newest `equity_snapshots` row instead of seeded demo numbers.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `{"ok":false,"error":"Unauthorized"}` from `guard-check` | Bearer missing, or not the `service_role` key. With `verify_jwt = true` the platform rejects an anon key here too. |
| `cron.job` empty after `db push` | pg_cron unavailable on the plan, or the migration failed — read the `supabase db push` output. |
| Job runs, `snapshots: 0` | No account has both `is_active = true` and `equity_guard_enabled = true`. |
| `skipped` climbs every minute | `metaapi_account_id` is null (never connected) or MetaAPI is unreachable — expected until `METAAPI_TOKEN` works. |
| Guard stays STALE in the app | No snapshot in the last 3 minutes → check step 2 before suspecting the app. |
| Apple sign-in "could not be verified" | `aud` mismatch: Supabase's Apple config points at a different bundle/Service ID. |
| Google sign-in works on iOS but not Android | `GOOGLE_SERVER_CLIENT_ID` missing, or the SHA-1 is not on the Android OAuth client. |
| Replay says "no bars cached" but the row exists in `prices_cache` | Migration 0008 is not applied. RLS with no policy returns an **empty set, not an error** — so this looks like missing data rather than a denied read. Run the 3a gate; if check 1 returns `0`, the `read cached bars` policy is missing. |
| `prices_cache` insert from the SQL Editor succeeds | Expected — you are `postgres`, which bypasses RLS. It proves nothing either way; test writes via PostgREST with a user JWT (3a gate, check 3). |