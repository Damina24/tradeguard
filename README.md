# TradeGuard — Forex Signals

Mobile-first forex / gold trading app: prop drawdown guard, auto journal, XAUUSD signals and
copy-trading. Flutter (iOS + Android) on Supabase, MetaAPI, FCM, RevenueCat and OpenAI.

- **Store title:** `TradeGuard - Forex Signals`
- **Bundle ID:** `com.tradeguard.app`

## Status: Phase 0 (scaffold)

The app boots in **mock mode** with seeded demo data (EVAL $100k + FUNDED $50k) so every screen
works without any keys.

## Quick start

```bash
# 1. Install Flutter 3.22+ (add to PATH), then:
flutter --version

# 2. If platform runners are missing (fresh clone), regenerate them once:
flutter create --platforms=android,ios --org com.tradeguard .

# 3. Dependencies + checks
flutter pub get
flutter analyze
flutter test

# 4. Run (mock mode)
flutter run

# 5. Run with real backend once keys exist
copy env\dev.example.json env\dev.json   # then fill the __PLACEHOLDER__ values
flutter run --dart-define-from-file=env/dev.json
```

## Project layout

```
docs/       16 build + store-compliance documents
store/      listing copy + publishing checklist
lib/
  core/     theme, router, models, services (mock + providers), utils, widgets
  features/ guard | journal | tools | signals | settings
supabase/   migrations + edge function stubs
test/       trading math, guard logic, widget smoke tests
```

## Compliance (non-negotiable)

- Display name stays `TradeGuard - Forex Signals`.
- No profit guarantees; risk disclaimer on paywall, copy confirm, signals and settings.
- No `MT4/MT5/MetaTrader/TradingView` in the store display name.
- Broker passwords are never stored; only the MetaAPI account id.
- Copy-trading is **paper mode by default**.

See `AGENTS.md`, `ROADMAP.md` and `docs/IMPLEMENTATION_PLAN.md` for the full plan.
