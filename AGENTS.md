# AGENTS.md — TradeGuard Build Guide

Purpose: instructions for AI agents and humans working in this repo.

## Product

- App name (store): `TradeGuard - Forex Signals`
- Bundle ID / package: `com.tradeguard.app`
- Subtitle: `Prop Tracker & Gold Alerts`
- One app, feature-flagged: Funded Guard (core) + SignalPilot (Phase 3).

## Tech Stack (locked)

| Layer | Choice |
|---|---|
| Mobile | Flutter 3.22+ / Dart 3.4+ (single codebase iOS + Android) |
| State | Riverpod (flutter_riverpod) |
| Routing | go_router |
| Backend | Supabase (Postgres, Auth, Realtime, Storage, Edge Functions) |
| Broker data | MetaAPI Cloud (`metaapi.cloud`) REST + WebSocket |
| Push | Firebase Cloud Messaging + APNs |
| Payments | RevenueCat + Apple IAP + Google Play Billing |
| AI | OpenAI `gpt-4o-mini` via Supabase Edge Function (server-side only) |
| Charts | fl_chart (guard/journal), TradingView lightweight-charts (Phase 2) |
| CI | GitHub Actions + Codemagic (cloud iOS builds; dev machine is Windows) |

## Conventions

- Feature-first folders: `lib/features/<feature>/{data,domain,presentation,widgets}`.
- Core in `lib/core/{theme,router,services,utils,models,constants}`.
- No business logic in widgets. Services only in `lib/core/services` or feature `data`.
- All money math in `TradingMath` util with unit tests.
- Never log or persist broker passwords; store only `metaapi_account_id`.
- Every user-visible risk surface must show the risk disclaimer string from `AppStrings.riskDisclaimer`.

## Placeholders

Search for `__PLACEHOLDER__` and fill before release. See `docs/IMPLEMENTATION_PLAN.md`.

```env
SUPABASE_URL=__PLACEHOLDER__
SUPABASE_ANON_KEY=__PLACEHOLDER__
SUPABASE_SERVICE_KEY=__PLACEHOLDER__
METAAPI_TOKEN=__PLACEHOLDER__
OPENAI_API_KEY=__PLACEHOLDER__
REVENUECAT_IOS_KEY=__PLACEHOLDER__
REVENUECAT_ANDROID_KEY=__PLACEHOLDER__
FCM_SERVER_KEY=__PLACEHOLDER__
TWELVEDATA_KEY=__PLACEHOLDER__
GOOGLE_SERVER_CLIENT_ID=__PLACEHOLDER__
GOOGLE_IOS_CLIENT_ID=__PLACEHOLDER__
APPLE_WEB_CLIENT_ID=__PLACEHOLDER__
```

`SUPABASE_SERVICE_KEY` lives only in Vault + `supabase secrets` — never in `env/*.json` on a device.
Full bring-up order: `docs/BACKEND_DEPLOY.md`.

## Common Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run --dart-define-from-file=env/dev.json
flutter build appbundle --release
flutter build ipa --release        # via Codemagic
dart run build_runner build --delete-conflicting-outputs
supabase db push                    # after keys configured
supabase functions deploy guard-check sync-trades ai-review ai-analyze-chart copy-signal
```

## App runs in MOCK mode by default

If `SUPABASE_URL` is not set, the app uses `lib/core/services/mock_*` services with seeded
demo data (EVAL $100k FTMO, FUNDED $50k). This lets the whole UI run without any keys.

## Compliance guardrails (do not violate)

- No claims of guaranteed profit, win rate promises, or "best signals".
- No `MetaTrader`, `MT4`, `MT5`, `TradingView` inside the app display name.
- Display name must remain `TradeGuard - Forex Signals`.
- Risk disclaimer on: paywall, copy-signal confirm, signals screen footer, settings.
- No broker credentials stored client-side or server-side.
