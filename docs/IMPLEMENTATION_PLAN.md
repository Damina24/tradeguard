# IMPLEMENTATION_PLAN.md — TradeGuard

Status legend: ✅ done · 🔄 in progress · ⬜ todo · 🧑 human gate

## Phase 0 — Scaffold

| # | Task | Status |
|---|---|---|
| 0.1 | Docs pack | ✅ |
| 0.2 | pubspec + analysis_options | ✅ |
| 0.3 | Theme + tokens | ✅ |
| 0.4 | Router + app shell + bottom nav | ✅ |
| 0.5 | Models + mock services + demo data | ✅ |
| 0.6 | TradingMath + unit tests | ✅ |
| 0.7 | Supabase migration + edge function stubs | ✅ |
| 0.8 | env samples + .gitignore + CI | ✅ |
| 0.9 | `flutter pub get` + analyze + test pass | ✅ (Flutter 3.47.6, 104 tests, APK builds) |
| 0.10 | Git init + first commit | ⬜ |

## Phase 1 — Guard MVP

| # | Task | Status |
|---|---|---|
| 1.1 | Auth — email/password, sign-up, reset, router guard | ✅ Apple/Google too (`SocialAuthService`; provider keys 🧑) |
| 1.2 | Broker connect flow → `meta-connect` | ✅ (mock + live service, Edge Function implemented) |
| 1.3 | guard-status provider (mock → live repositories) | ✅ |
| 1.4 | Guard Home UI wired | ✅ |
| 1.5 | FCM topic subscription + 70/90 in-app alert | ✅ server side too: `guard-check` scheduled 1/min by pg_cron, service-role guarded, 30-day retention |
| 1.6 | Calculators (lot/RR/margin/dd) | ✅ |
| 1.7 | P&L calendar + trade list | ✅ |

Four deliberate calls worth recording:

1. **The 70/90 *push* is server-side.** `docs/BACKEND_SCHEMA.md` gives `guard-check` (cron 1/min)
   ownership of pushing. The app therefore only subscribes the device to that account's FCM topic
   and raises an immediate in-app banner; it does not build its own system notifications, which
   would have meant adding `flutter_local_notifications` and duplicating server logic.
2. **Mock mode auto-signs-in.** `Services.isMock` is true whenever `SUPABASE_URL` is empty, so
   `authProvider` starts as a demo user and the router never shows `/auth`. That preserves the
   Phase 0 exit criterion (boots to Guard) while live mode still requires a real session.
3. **A freshly connected account starts at its initial balance, not at a live reading.**
   `connectedAccount` seeds equity/balance/peak to `initialBalance` and `dailyPnl` to 0. Inventing a
   P&L would make the guard look live when it is not; instead `guard-check` writes the first real
   `equity_snapshots` row within a minute and the Guard screen degrades to STALE until then.
4. **The password is never allowed to rest anywhere.** It exists only inside the
   `BrokerConnectionRequest` built by the sheet, is relayed to `meta-connect`, and the controller is
   cleared the moment the call returns. `ConnectState` — the only object the widget tree observes —
   has no field that could hold it, and error strings from MetaAPI are never echoed verbatim
   because a provider error can quote the login back.

Remaining Phase 1 work is gated on Supabase + MetaAPI + Firebase credentials 🧑. The full
bring-up, including the Vault secrets the cron job needs, is `docs/BACKEND_DEPLOY.md`.

5. **Social sign-in verifies on the server, not the client.** `sign_in_with_apple` /
   `google_sign_in` only produce an ID token; `SupabaseAuthRepository` exchanges it via
   `signInWithIdToken`, so GoTrue checks the signature, `aud`, `iss` and — for Apple — the nonce.
   The raw nonce is what travels back to GoTrue; the SHA-256 we sent to Apple is not, which is the
   whole point of the nonce.
6. **A dismissed Apple/Google sheet is not an error.** `SocialAuthResult.cancelled` maps onto
   `AuthOutcome.done()`, so backing out of the popup leaves the screen untouched. Every other failure
   becomes `SocialAuthException` with trader-safe copy — raw plugin strings are never rendered.
7. **`guard-check` authenticates its own caller.** `verify_jwt = false` means the platform checked
   nothing, which would let anyone with the URL make us spend MetaAPI allowance on demand. It now
   requires the service-role bearer that pg_cron presents.

## Phase 2 — Journal + AI

| # | Task | Status |
|---|---|---|
| 2.1 | CSV/HTML import + dupe handling | ⬜ |
| 2.2 | sync-trades worker | ⬜ |
| 2.3 | Trade detail + grading + screenshots | ⬜ |
| 2.4 | Pattern views + leaks UI | ⬜ |
| 2.5 | ai-review card | ⬜ |
| 2.6 | Replay lite | ⬜ |

## Phase 3 — Signals + Copy

| # | Task | Status |
|---|---|---|
| 3.1 | Signals feed + stats | ⬜ |
| 3.2 | Volatility radar | ⬜ |
| 3.3 | AI chart analysis | ⬜ |
| 3.4 | Copy confirm sheet + lots math | ⬜ |
| 3.5 | copy-signal edge (paper default) | ⬜ |
| 3.6 | Live copy consent + kill switch | ⬜ |

## Phase 4 — Monetize + Ship

| # | Task | Status |
|---|---|---|
| 4.1 | RevenueCat paywall + entitlements | ⬜ |
| 4.2 | Cashback WebView | ⬜ |
| 4.3 | Analytics + crash reporting | ⬜ |
| 4.4 | Icons/splash/store graphics | 🧑 |
| 4.5 | Host privacy + deletion pages | 🧑 |
| 4.6 | Internal → Closed (12 testers × 14d) → Production | 🧑 |

## Human Input Checklist

Replace every `__PLACEHOLDER__` before release:

1. `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_KEY` 🧑
2. `METAAPI_TOKEN` 🧑
3. `OPENAI_API_KEY` 🧑
4. `REVENUECAT_IOS_KEY`, `REVENUECAT_ANDROID_KEY` 🧑
5. `FCM_SERVER_KEY` + `google-services.json` + `GoogleService-Info.plist` 🧑
6. `TWELVEDATA_KEY` 🧑
7. Domain (`tradeguard.app` / `gettradeguard.com`) + hosted `/privacy`, `/terms`, `/delete-account` 🧑
8. Store graphics (icon 512, feature 1024x500, screenshots) 🧑
9. Play Console + Apple Developer accounts, D-U-N-S for org 🧑
10. Closed tester emails `TESTER_01..12` 🧑
11. Affiliate broker links (Exness / PU Prime) 🧑

## Closed Testing Plan

1. Build AAB → Internal testing → install on own device.
2. Promote to Closed testing track, add ≥12 tester emails.
3. Keep track live ≥14 consecutive days, gather feedback.
4. Only then request Production access (personal accounts post Nov-2023 rule).
5. Production staged rollout 20% → 100%.

Feedback form template: install ease, guard clarity, alert usefulness, bugs, would-pay.
