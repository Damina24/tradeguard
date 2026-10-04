# APPFLOW.md — TradeGuard

## 1. First Run

```
Launch → S1 Onboarding (3 slides) → Sign up (email / Apple / Google)
      → S2 Connect Broker (Demo mode ON by default)
      → S3 Guard (populated with demo EVAL/FUNDED)
```

Skip path: "Explore demo" → S3 with seeded demo accounts, no auth required locally.

## 2. Guard Loop (the retention loop)

```
Push wake (70% / 90%) or daily habit
   → S3 Guard load
     → fetch guard-status (cache → live)
       → render meters
         → user acts: reduce size (Tools), STOP (consent), or journal note
           → event logged (analytics)
```

## 3. Journal Flow

```
S4 Journal → pick day on CalendarHeat
   → list filtered
     → open S5 Trade Detail
        → grade + tags + notes + screenshot
          → AI Review (Phase 2) → suggestion
            → saved (queued offline if needed)
```

## 4. Import Flow

```
Tools/Settings → Import trades
  → choose source (MT5 HTML / MT4 HTML / cTrader CSV / CSV)
    → parse preview (rows, dupe check by metaapi_trade_id/platform id)
      → confirm → upsert trades → recompute analytics
```

## 5. Signal → Copy Flow

```
S7 Signals → SignalCard
  → tap Copy → S8 bottom sheet
     → pick account(s) + risk % (default 1%)
       → lots = (balance * risk%) / (sl_pips * pip_value(symbol))
         → preview: lots, pip value, max loss, R
           → Paper mode? yes → simulate fill (log only)
                          no  → consent modal (first time only)
                                → copy-signal Edge Function → MetaAPI order
                                  → live follow row + push confirmation
```

Copy guardrails: max lots cap, max concurrent follows, kill switch, per-account permission.

## 6. AI Chart Analysis Flow

```
S7 → AI Analyze → image picker → upload to Storage (temp)
  → ai-analyze-chart → result sheet {bias, levels, entry, sl, tp}
    → optional "Create signal draft" (admin only) or "Add to journal"
```

## 7. Auth Flow

```
Sign up → verify email → session (Supabase JWT)
Sign in → splash checks session → S3 if onboarded else S2
Sign out → clear local, keep nothing but prefs
Delete account → Settings → confirm twice → Edge Function purges data (30d SLA)
```

## 8. State Machine (guard)

```
LOADING → OK | STALE | WARN(>=70) | CRITICAL(>=90) | BREACH(>=100) | ERROR
Transitions: any → ERROR on fetch fail; BREACH → CLOSED if equity guard fired.
```

## 9. Deep Links

`tradeguard://account/<id>` → S3, `tradeguard://signal/<id>` → S7 detail,
`tradeguard://paywall` → S9. Push payloads carry these.
