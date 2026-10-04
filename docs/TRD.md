# TRD.md — TradeGuard Technical Requirements

## 1. Architecture

```
Flutter App (iOS/Android)
 ├─ Riverpod providers
 ├─ go_router navigation
 ├─ Repositories ──► Supabase (Postgres + RLS + Storage + Auth)
 │                    └─ Edge Functions
 │                        ├─ guard-check     (cron 1/min)
 │                        ├─ sync-trades     (MetaAPI pull)
 │                        ├─ ai-review       (OpenAI)
 │                        ├─ ai-analyze-chart(OpenAI vision)
 │                        └─ copy-signal     (MetaAPI order)
 ├─ FCM push  ◄── Edge Function triggers
 └─ RevenueCat SDK ◄── Apple IAP / Play Billing
                        ▲
             MetaAPI Cloud (MT4/MT5/cTrader)
```

## 2. Project Layout

```
lib/
  main.dart
  app.dart
  core/
    theme/app_theme.dart app_colors.dart app_text_styles.dart
    router/app_router.dart
    constants/app_strings.dart app_config.dart
    models/ (account, trade, signal, guard_status, ai_review)
    services/ (supabase_client, mock_*, metaapi, revenuecat, notifications, analytics)
    utils/trading_math.dart formatters.dart date_utils.dart
  features/
    onboarding/  guard/  journal/  tools/  signals/  settings/
      each: {data/ domain/ presentation/ widgets/}
    each: {data/ domain/ presentation/ widgets/}
supabase/
  migrations/0001_init.sql ...
  functions/guard-check/ sync-trades/ ai-review/ ai-analyze-chart/ copy-signal/
test/
  trading_math_test.dart  guard_logic_test.dart  widget_smoke_test.dart
```

## 3. Dependencies (pubspec)

Core: `flutter_riverpod`, `go_router`, `supabase_flutter`, `intl`, `fl_chart`,
`shared_preferences`, `flutter_secure_storage`, `image_picker`, `file_picker`,
`csv`, `http`, `url_launcher`, `webview_flutter`, `firebase_core`, `firebase_messaging`,
`purchases_flutter` (RevenueCat), `metaapi_cloud_sdk` (or REST via http), `logger`.

Dev: `flutter_lints`, `mocktail`, `build_runner`.

## 4. Environments

`env/dev.json`, `env/staging.json`, `env/prod.json` consumed via
`--dart-define-from-file`. Absent config ⇒ MOCK mode.

## 5. MetaAPI Integration

- Server-side only for token. App calls Edge Function `meta-connect` with login/server.
- Store `metaapi_account_id` only. Read-only scopes for journal. Trade scope requested
  only when user opts into live copy (explicit consent dialog).
- WebSocket for live equity; fallback REST poll 30s.

## 6. Guard Engine

- `equity_snapshots` row per minute per account (cron Edge Function).
- `daily_pnl` resets at broker rollover (server offset configurable per account).
- `drawdown_used`: static = `initial_balance - equity`; trailing = `peak_equity - equity`
  where peak = `MAX(equity)` since last reset.
- Thresholds: warn 70%, critical 90%, breach 100% → FCM + in-app banner.
- Equity Guard (opt-in): on breach or manual STOP → `copy-signal` close-all.

## 7. AI

- Edge Functions hold `OPENAI_API_KEY`. Prompts versioned in function source.
- `ai-review`: input trade fields → JSON `{summary, leak, score, suggestions[]}`.
- `ai-analyze-chart`: input Storage image URL → JSON `{bias, levels[], entry, sl, tp[]}`.
- Never send broker credentials or account numbers to the model.

## 8. Payments

- RevenueCat entitlement capability: `pro`, `elite`, `lifetime`.
- Offerings: `default` (Pro/Elite monthly + annual) and `lifetime`.
- Restore purchases on Settings. Manage/cancel redirects to store.

## 9. Non-functional

- p95 guard API < 800ms; app cold start < 3s; crash-free > 99%.
- Offline: last guard snapshot cached; journal writes queued.
- Security: RLS on all tables, TLS only, secure storage for tokens, no PII in logs.
- Accessibility: min tap 44px, contrast AA, dynamic text scale support.

## 10. CI/CD

- GitHub Actions: analyze + test on PR.
- Codemagic: iOS build/sign (no local Xcode), Play AAB build, internal distribute.
