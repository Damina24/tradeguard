# PRD.md — TradeGuard (Funded Guard + SignalPilot)

## 1. Press Release

For forex and gold mobile traders and prop-firm challengers who blow accounts on math, not
strategy, **TradeGuard** is the mobile-first guardian that keeps you funded. Unlike
desktop-only journals (TradeZella), unverified signal apps (SignalPro), or Windows-only
offline tools (PitLog), TradeGuard combines a live MT4/MT5 drawdown guard, auto-journal,
verified signals, and one-tap copy in your pocket.

One saved challenge (~$500) pays for ~20 months.

## 2. Problem

- Prop traders compute trailing drawdown and daily loss in their head and blow breaches.
- Spreadsheets drift from broker fills within days.
- Signal apps show screenshots, not a verified live ledger.
- Journals are desktop/web-first and painful on a phone.

## 3. Target Users

1. **Prop challenger** (highest LTV): FTMO / FundedNext / E8, EVAL + FUNDED accounts. Needs guard.
2. **Gold scalper**: XAUUSD, follows signals, wants copy + risk sizing.
3. **Developing retail trader**: needs journal, patterns, calculators.

## 4. Success Metrics

| Metric | Target | Horizon |
|---|---|---|
| D7 guard-open rate | > 40% | 30 days post-launch |
| Trial → paid conversion | > 12% | 60 days |
| Journal import success | > 90% | Phase 2 exit |
| Breach-save events / user / mo | ≥ 1 | 90 days |
| Store rating | ≥ 4.5 | 90 days |

Guardrail metrics: crash-free sessions > 99%, p95 guard fetch < 800ms, copy error < 1%.

## 5. Scope — 5 Tabs

```
Onboarding → Connect Broker → [Guard | Journal | Tools | Signals | Settings]
```

1. **Guard (Home):** account switcher, daily-loss meter (amber 70 / red 90), trailing
   drawdown distance, profit-to-payout %, equity sparkline, STOP (equity guard) button.
2. **Journal:** month P&L calendar, trade list + filters, trade detail, grading, notes,
   screenshots, pattern leaks, AI review card.
3. **Tools:** lot size, RR, margin, drawdown sim, economic calendar, session clock.
4. **Signals:** live feed, verified stats, volatility radar, AI chart analysis, copy w/ preview.
5. **Settings:** accounts, subscription, cashback, risk disclaimer, delete account.

## 6. Non-Goals (v1)

- No actual brokerage / order routing beyond MetaAPI copy.
- No crypto wallet, no stock/options support (futures/CFD display only).
- No social feed / chat.
- No news publishing.

## 7. Pricing

| Tier | Price | Key | Entitlement |
|---|---|---|---|
| Free | $0 | 1 account, manual import, 3 AI/day, 3 signals/day | — |
| Pro | $19.99/mo (test $29.99) | unlimited accounts, live guard push, unlimited AI review, VIP signals, copy 1 acct | `pro` |
| Elite | $49.99/mo | copy unlimited, advanced analytics, Discord | `elite` |
| Lifetime | $197 (first 500) | everything, forever | `lifetime` |

Broker rebate (Exness / PU Prime, 40–60% spread share) funds the Free tier.

## 8. Phase Mapping

- P1 Guard = tabs 1 + tools. P2 Journal = tab 2. P3 Signals = tab 4. P4 monetize = tab 5 + paywall.

## 9. Risks & Mitigation

| Risk | Mitigation |
|---|---|
| MetaAPI downtime | cache last good snapshot, degrade banner, retry backoff |
| Store rejection (finance) | disclaimers everywhere, no profit claims, deletion URL, honest data safety |
| Copy-trade loss | paper mode default ON, explicit consent, max-lots cap, kill switch |
| Churn after challenge | pivot value to journal + signals + patterns |
| Trademark | never use MT4/MT5/TradingView in display name |

## 10. Not Building (v1) — explicit

Advanced options analytics, multi-language beyond EN, web dashboard, referral program UI,
community feed, automated strategy marketplace.
