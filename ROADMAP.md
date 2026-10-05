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

- ✅ CSV / HTML import (MT5, MT4, cTrader) + auto-sync worker
- ✅ Trade detail, grading A–D, notes (screenshot upload to Storage still ⬜ — tracked gap from S5)
- ✅ Pattern tracker: `v_patterns` consumed as-is (symbol / session / hour / day), conservative
      leak detector (net-negative slice + loss concentration, min 5 trades, confidence labelled).
      Migration 0006 makes the analytics views RLS-respecting — 🧑 apply + verify live
- ✅ `ai-review` Edge Function + AI Review card: `{trade_id} -> {summary, leak, score, suggestions[]}`.
      Trade fields reach the model through an **allowlist** projection (no ids, no notes, no
      screenshot path), the prompt is versioned in source, and the response is clamped/capped
      before it is stored or rendered. `AiReviewCard` sits on S5 below the deterministic checklist
      and grade, so the trader reads a verdict they can check for themselves first. A failed
      refresh keeps the previous review visible and is never shown as "no review yet"; mock mode
      labels itself `OFFLINE DEMO`. Migration 0007 narrows `ai_reviews` to SELECT (a client could
      otherwise forge its own reviews) and adds the `(user_id, trade_id)` idempotency key —
      🧑 apply + verify live
- ✅ Backtest replay lite: a bar-by-bar engine over cached OHLC bars. The trader picks a direction, a
      stop width in bar-ranges and a target R; the replay fills at the first bar that trades through
      the entry and follows it bar by bar (play / step / jump) until the stop or the target. Every fill
      and exit rule is pessimistic — a bar spanning both the stop and the target is a loss, the entry
      bar cannot also be the exit bar, and an unresolved position is labelled rather than closed at a
      convenient price. A whole-series `ReplayScan` re-anchors the same setup on every bar and refuses
      to print a rate below 10 trades. TwelveData is fetched **server-side only** by `market-bars`
      (`TWELVEDATA_KEY` never ships in the APK; the key stays in `supabase secrets` and the field in
      `AppConfig` is a documented placeholder that must remain empty); migration 0008 opens
      `prices_cache` for authenticated reads and revokes every client write, closing a cross-tenant
      route where one user could have posted bars that another trader's backtest charted — 0008
      approved but **not yet verified**: blocked on the 3a gate in `docs/BACKEND_DEPLOY.md`, which
      must be run through PostgREST with a user JWT (the SQL Editor bypasses RLS and gives a false
      green)

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
