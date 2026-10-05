# UI_UX_DESIGN.md — TradeGuard

## 1. Design Principles

1. One number that matters per card (guard first).
2. Green = safe, amber = watch, red = act now. Never rely on color alone (add icon + text).
3. Thumb-reachable. Primary action bottom third.
4. Trust: show data source and freshness timestamp on every live widget.

## 2. Theme

| Token | Value |
|---|---|
| Background | `#0A0E17` |
| Surface | `#121826` |
| SurfaceAlt | `#1A2233` |
| Primary (safe) | `#00E676` |
| Warning | `#FFB300` |
| Danger | `#FF3D5A` |
| TextPrimary | `#F5F7FA` |
| TextMuted | `#8A94A6` |
| Accent | `#3B82F6` |
| Radius | 8 (cards 16) |
| Font | Inter (fallback SF Pro / Roboto) |
| Spacing | 4 / 8 / 12 / 16 / 24 / 32 |

Dark mode is default and primary. Light mode Phase 2 (out of v1 scope but tokens defined).

## 3. Components

- `GuardMeter` — horizontal bar, % label, color by threshold, icon.
- `StatCard` — label, value, delta, sparkline slot.
- `AccountChip` — nickname + phase pill (EVAL/FUNDED) + color dot.
- `SignalCard` — pair, direction pill, entry/SL/TP rows, confidence, Copy button.
- `TradeRow` — symbol, direction, P&L colored, R multiple, grade.
- `CalendarHeat` — month grid green/red by net P&L.
- `DisclaimerNote` — muted risk text, used on paywall/copy/signals.
- `PrimaryButton`, `GhostButton`, `DangerButton`.

## 4. Screens (9)

### S1 Onboarding
3 slides: "Never blow daily loss", "Auto-journal every fill", "Copy verified gold signals".
CTA: Get started. Secondary: I have an account. Risk note at bottom.

### S2 Connect Broker
Platform selector (MT4 / MT5 / cTrader). Explain read-only. Demo mode toggle (default ON).
Fields: login, server, (password never stored - relayed to MetaAPI). CTA Connect.

### S3 Guard (Home)
- Top: AccountChip row (EVAL $100k, FUNDED $50k) + refresh + freshness.
- Hero: Daily Loss Used GuardMeter + "Left: $X of $Y".
- Row: Trailing Drawdown distance | Profit to Target %.
- Equity sparkline card (24h).
- Today: P&L, Win%, Trades.
- Big buttons: STOP (danger, close-all consent), Add Trade (manual), Journal shortcut.

### S4 Journal
- CalendarHeat month.
- Filter chips: symbol / session / setup / grade.
- Stats strip: Net P&L, Win%, PF, Avg R.
- Trade list (TradeRow) → S5.

### S5 Trade Detail
- Chart snapshot image (if any), entry/exit/SL/TP, MFE/MAE, R.
- Grade selector A–D, tags, notes, screenshot upload.
- AI Review card (Phase 2).
- Rule checklist compliance bar.

### S6 Tools
- Grid: Lot Size, Risk/Reward, Margin, Drawdown Sim.
- Economic calendar list (impact dots).
- Session clock: London / NY open countdown.

### S-replay — Backtest replay lite (child of Tools, task 2.6)
- Symbol chips + timeframe; provenance line (`Cached market data · N bars · updated 4m ago`, or a
  `SYNTHETIC DEMO` chip for generated bars).
- Price chart with the setup's entry / stop / target drawn as labelled lines.
- Transport: reset, step back, play/pause, step forward, skip to end, plus a "bar N of M" counter.
- Setup controls: direction, stop width in bar-ranges, target R (including "No target"). The derived
  entry / stop / target are printed as a block of prices, never hidden behind the controls.
- Verdict card: target hit / stop hit / still open / never filled / invalid — each in its own words,
  with fill price, exit bar, bars held, MFE and MAE in R.
- Scan card: every bar tested. Sample size and floor printed first; **no rate at all** below 10 trades.
- Backtest disclaimer at the foot (hypothetical, fixed fill assumptions, no spread/slippage, past
  performance is not indicative).

### S7 Signals
- LIVE badge + last update.
- SignalCard list.
- Volatility Radar: score + top newswires.
- AI Analyze button → pick image → result sheet.
- Footer disclaimer.

### S8 Copy Confirm (bottom sheet)
- Signal summary, account picker, risk % slider, computed lots, pip value, max loss.
- Paper mode pill. Confirm copy → result toast. Disclaimer.

### S9 Settings / Paywall
- Accounts management, subscription status, restore, cashback banner, links
  (privacy, terms, disclaimer), version, Sign out, **Delete account**.
- Paywall: Free vs Pro vs Elite table + Lifetime card, disclaimer.

## 5. Motion

120–200ms ease-out transitions. GuardMeter animates on change. No confetti on wins
(compliance: avoid encouraging gambling-like behavior).

## 6. Empty / Error / Loading

- Every list has skeleton shimmer, empty illustration + CTA, and error retry.
- Stale data (> 3 min) shows "stale" chip.

## 7. Accessibility

44px min targets, AA contrast, semantic labels on meters, no color-only meaning.
