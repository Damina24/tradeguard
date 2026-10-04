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

That applies `0001_init.sql` … `0004_guard_check_cron.sql`. The last one needs two Vault secrets, so
insert them **before** pushing it — or re-run it afterwards:

```sql
-- Dashboard → SQL Editor, or: psql "$DATABASE_URL"
select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
select vault.create_secret('<service_role key>', 'service_role_key');
```

Why Vault instead of a literal in the SQL: `cron.job.command` is a plain string in a table anyone
with SQL access can read. Reading the secret at run time keeps the key out of it. The job calls
`guard-check` with `Authorization: Bearer <service_role>`, which is what the function now requires.

```sql
select jobname, schedule, active from cron.job where jobname = 'guard-check-minutely';
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
supabase secrets set SUPABASE_SERVICE_KEY=<service_role>
supabase secrets set FIREBASE_SERVICE_ACCOUNT='{"type":"service_account","project_id":"…", …}'
```

| Secret | Needed for | If missing |
|---|---|---|
| `SUPABASE_SERVICE_KEY` | the guard worker | function 500s |
| `METAAPI_TOKEN` | reading live equity | falls back to the last snapshot; Guard shows STALE |
| `FIREBASE_SERVICE_ACCOUNT` | the 70/90 push | numbers are stored, no notification |

`FIREBASE_SERVICE_ACCOUNT` is the **whole** service-account JSON (Firebase console → Project settings
→ Service accounts → Generate new private key). Quoting matters: an unquoted value containing spaces
or `\n` breaks the secret.

```bash
supabase functions deploy guard-check meta-connect
```

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