# ROADMAP.md — TradeGuard

Legend: ✅ done · 🔄 in progress · ⬜ not started · 🧑 human input required

## Phase 0 — Scaffold (Day 1–3) ✅

- ✅ Docs pack (AGENTS, ROADMAP, PRD, TRD, UI/UX, AppFlow, Backend schema, Implementation plan)
- ✅ Store compliance docs (privacy, terms, disclaimer, deletion, data safety, content rating)
- ✅ Flutter project structure, theme, router, Riverpod
- ✅ Mock services + demo data
- ✅ `flutter pub get` / analyze / test pass (Flutter 3.47.6 — analyze clean, 104 tests green,
      `flutter build apk --debug` OK)
- ⬜ GitHub repo + first commit

Exit criteria: app builds, boots to Guard screen with mock EVAL/FUNDED accounts, tests green.

## Phase 1 — Guard MVP (Week 1–3) 🔄

- ✅ Service layer: mock ↔ Supabase repositories behind a `Services` locator (auth / accounts /
  trades / push), so the app boots with no backend and switches to live via `SUPABASE_URL`
- ✅ Auth: email + password, sign-up, password reset, router guard. Mock mode auto-signs-in a demo
  user so the app still boots straight to Guard. Apple + Google sign-in behind
  `SocialAuthService` (ID token → `signInWithIdToken`); provider credentials still 🧑
- ✅ Broker accounts CRUD + connect flow (MetaAPI via Edge Function, mock first): Settings lists
  each account with an equity-guard toggle and a confirmed remove; the connect sheet relays
  credentials to `meta-connect` and keeps only `metaapi_account_id`
- ✅ Equity snapshot worker + `guard-check`: scheduled 1/min by pg_cron (migration 0004), requires the
  service-role bearer, prunes snapshots past 30 days, and owns the 70/90 FCM push
- ✅ Guard Home: daily-loss meter, trailing drawdown distance, profit-to-target, wired to repositories
- ✅ Alerts: device subscribes to the account's FCM topic; 70/90 crossings raise an in-app critical
  banner (de-duplicated, so a 1/min refresh never spams)
- ✅ Lot size / RR / margin / drawdown calculators
- ✅ P&L calendar + trade list from `trades` table

Exit: trader can watch live guard numbers and receive a breach alert.

> Phase 1 is code-complete. Deploy it with **`docs/BACKEND_DEPLOY.md`** — the remaining steps are
> credentials (Supabase project, MetaAPI token, Firebase, Apple/Google OAuth clients) and cannot be
> automated. Until then the app runs in mock mode with seeded demo data.

## Phase 2 — Journal + AI (Week 4–6) ⬜

- CSV / HTML import (MT5, MT4, cTrader) + auto-sync worker
- Trade detail, grading A–D, notes, screenshot upload (Supabase Storage)
- Pattern tracker SQL views (best hour / day / setup / session leaks)
- `ai-review` Edge Function + AI Review card
- Backtest replay lite (bar-by-bar, TwelveData cache)

Exit: D7 guard-open > 40%, journal import success > 90%.

## Phase 3 — Signals + Copy (Week 7–9) ⬜

- Signals feed + admin post + verified stats
- Volatility radar (newswire score, static seed then live)
- AI chart analysis (screenshot upload)
- Copy-signal: risk% → lots → MetaAPI order. **Paper mode ON by default.** 🧑 review before live
- Master/slave multi-account routing

Exit: copy preview accuracy 100% vs lot formula tests, live copy gated behind explicit opt-in.

## Phase 4 — Monetize + Harden + Ship (Week 10–12) ⬜

- RevenueCat paywall + entitlements (`pro`, `elite`, `lifetime`)
- Broker cashback WebView (Exness / PU Prime) 🧑 affiliate links
- Analytics (PostHog placeholder) + crash reporting
- Icons / splash / store graphics 🧑 design assets
- Privacy URL, deletion URL, listing copy 🧑 domain + hosting
- Internal → Closed testing ≥12 testers × 14 days 🧑 tester emails
- Production staged rollout 20% → 100%

Exit: live on Google Play + App Store, placeholders replaced.

## Human Gates (cannot be automated)

| Gate | Phase | Placeholder |
|---|---|---|
| Install Flutter/Dart SDK | 0 | — |
| Supabase project keys | 1 | `SUPABASE_*` |
| MetaAPI token | 1 | `METAAPI_TOKEN` |
| OpenAI key | 2 | `OPENAI_API_KEY` |
| RevenueCat keys | 4 | `REVENUECAT_*` |
| Domain + hosted legal pages | 4 | `__PLACEHOLDER_DOMAIN__` |
| Store graphics | 4 | `store/graphics/` |
| 12+ closed testers × 14 days | 4 | `TESTER_01..12` |
| Google Play + Apple accounts | 4 | — |
