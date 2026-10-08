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
| 0.10 | Git init + first commit | ✅ |

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

8. **Phase 2 reuses Phase 1's model rather than forking it.** `sync-trades` and the CSV/HTML
   importer both produce the same `TradeRecord` and persist through the same
   `TradeImportRepository`. A deal id is therefore recognised identically whether it arrived as
   a file the trader uploaded or as a page MetaAPI returned — which is what stops a manual
   import and the cron worker from producing two copies of the same trade.
9. **Migration 0005 corrects the trades dedupe key from `(user_id, external_id)` to
   `(account_id, external_id)`.** The original key was wrong for broker data: a deal id is
   unique only *within one broker account*, so a trader holding an FTMO and an Exness account
   would have had the second account's sync UPDATE the first account's row. The new key is
   also what `InMemoryTradeImportRepository` and `TradeRecord` already used, so this makes the
   database agree with the code.
10. **The sync cursor narrows the window; `external_id` guarantees correctness.** Each run
    re-reads 6 hours before the watermark on purpose, because brokers book commission and swap
    after a deal closes. The overlap is free because the upsert key is the deal id, not a
    timestamp — two trades can share a millisecond, and a broker can restate a close time. The
    watermark also only ever moves FORWARD, so a late correction cannot rewind progress and make
    an account re-read forever.
11. **A failed sync does not advance the watermark.** Otherwise trades that arrived during an
    outage would be skipped permanently. Failures bump `consecutive_failures`, which drives an
    exponential backoff capped at an hour so a dead account stops consuming the shared MetaAPI
    allowance on every five-minute tick.
12. **Grading reuses the product's own A–D vocabulary and nothing more.** The spec defines the
    four letters (`grade text -- A|B|C|D`) and a "rule checklist compliance bar", but no
    thresholds, so `TradeReview` is a transparent checklist whose every input is visible in its
    reasons — not a proprietary score. A hand-set `trades.grade` always beats the derived one.
    An A additionally requires the >= 1R target, because a 0.05R scalp that merely kept its
    stop and target would otherwise score a perfect checklist and grade A.
13. **The detail screen shows the persisted `pnl`, never a recomputed one.** Task 2.1 writes it
    as `profit + commission + swap` and Task 2.2's sync writes the same, so recomputing it in the
    client would risk the app and the database disagreeing about a trader's equity. `Trade.pnl`
    is read verbatim; `commission`/`swap` are read from the columns that already existed to
    explain it.
14. **The share card carries no account number, broker login or trade id.** It shows the account
    *nickname* only. Nothing on `Trade` is a credential, and the domain layer never sees one, so
    a screenshot of the card is safe to post.
15. **Task 2.4 consumes `v_patterns` and never reimplements it.** The view already computes
    `sum(pnl)`, `count(*)` and a win-rate mean per `(symbol, session, dow, hour)`.
    `PatternMetrics` only *recombines* those aggregates — summing sums and weighting the average
    by each row's own count — which is arithmetically identical to the `GROUP BY` Postgres would
    have produced for the coarser axis. A second client-side roll-up of the same statistic would
    be a second source of truth that could disagree with the database.
16. **Three things `v_patterns` does not project are therefore not shown: R multiple, costs and
    grade.** They live on `trades.r_multiple`, `trades.commission/swap` and `trades.grade`, none
    of which the view aggregates. Rather than invent a client-side version of each, the pattern
    layer leaves them with `TradeMetrics`/`TradeReview` (task 2.3), which already own them. The
    roadmap's "setup leaks" is the same story: `trades.setup` exists but the view does not group
    by it, so setup is deliberately not a pattern dimension yet.
17. **A leak is a recurring slice, never a losing trade.** `LeakDetector` reports only slices
    holding at least `minTrades` (5) trades, and a `LeakConfidence` label (small / moderate /
    large) is rendered next to every finding so a thin sample is visibly weaker than a solid one.
    The shipped mock seed deliberately includes a losing 4-trade `US30` slice precisely so this
    guard is exercised rather than assumed.
18. **Leak loss shares are computed per dimension, not globally.** The four dimensions are
    *overlapping* views of the same trades — every row appears in all four — so summing losses
    across them counts each loss four times and would make the concentration rule unreachable
    instead of merely strict. Within one dimension the slices are disjoint, so shares compare.
19. **Migration 0006 fixes a latent cross-account leak in both views.** Postgres does not apply a
    base table's RLS policies to a view by default: a plain `create view` runs with its owner's
    privileges, so `select * from v_patterns` returned *every* user's pattern history to anyone
    who could query it. Nothing read the views until task 2.4. `security_invoker = true` makes
    `trades`' `own trades` policy apply per row. This has **not** been executed against a live
    project — see the migration's own verification note.

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
8. **Task 2.5 removes the ability to forge an AI review, and takes the client out of the write
   path.** Migration 0002's `ai_reviews` policy was `for all`, which included INSERT and UPDATE.
   Harmless while nothing wrote to the table; the moment the AI Review card shipped, it meant any
   user could insert a review with `auth.uid() = user_id` and any text, and the card would render
   that fabrication as though a model had written it. Migration 0007 narrows it to SELECT, so the
   only writer is the Edge Function — and that function writes with the service role, which is why
   it re-derives the caller from the verified JWT and filters the `trades` read on
   `trades.user_id = <caller>`. `user_id` is never read from the request body, so there is no IDOR
   to attempt. This migration has **not** been applied to a live project.
9. **The prompt is built from an allowlist, and that is the privacy control.** `projectTradeFacts`
   copies only execution fields off our own `trades` row. `user_id`, `account_id`, `nickname`,
   `metaapi_account_id`, `notes` and `screenshot_url` cannot reach the model because they are never
   read — the free-text notes are excluded precisely because that is where a trader is most likely
   to have written an account number. `FORBIDDEN_PROMPT_FIELDS` is a tripwire for the next editor,
   not the enforcement.
10. **A failure is a banner, never a replacement.** If a refresh fails while a review is already on
    screen, the card shows the error AND keeps the review. Discarding a trader's stored feedback
    because a network call failed would be worse than the failure. And a failure is never rendered
    as "no review yet" — that would let a backend misconfiguration hide behind an inviting button.
11. **The offline mock says so on the card.** Mock mode produces reviews from the deterministic
    checklist (`TradeReview`), so mock and the A–D grade can never disagree — but a demo review
    unlabelled is indistinguishable from model output. `isStubbed` renders an `OFFLINE DEMO` chip.
12. **The score band lives in `core/models`, not in the widget.** The thresholds are a claim about
    the score; a claim that lives in a widget is a claim a test cannot check. `AiReviewBand` sits
    beside `AiReview` so `core` never has to import from `features`.

## Phase 2 — Journal + AI

| # | Task | Status |
|---|---|---|
| 2.1 | CSV/HTML import + dupe handling | ✅ (`TradeRecord`, `TradeFileParser` + registry, mock-first `TradeImportRepository`) |
| 2.2 | sync-trades worker | ✅ idempotent + incremental (`trade_sync_cursors`, `(account_id, external_id)` upsert, cron 5/min) |
| 2.3 | Trade detail + grading + screenshots | ✅ detail, deterministic A–D checklist grade, share card (screenshot upload still ⬜) |
| 2.4 | Pattern views + leaks UI | ✅ `PatternRow`/`PatternMetrics` over `v_patterns`, mock-first, conservative leak detector; migration 0006 makes the views RLS-respecting 🧑 (not yet applied live) |
| 2.5 | ai-review card | ✅ `ai-review` Edge Function (allowlist projection, prompt versioned in source) + `AiReviewCard` on S5, mock-first; migration 0007 makes `ai_reviews` SELECT-only and idempotent 🧑 (not yet applied live) |
| 2.6 | Replay lite | ✅ bar-by-bar replay engine (pessimistic fill rules), `ReplayScan` with a reporting floor, fl_chart chart + play/step transport, mock-first; `market-bars` Edge Function + migration 0008 open `prices_cache` for reads and revoke every client write — ✅ **LIVE 2026-10-06** (3a gate passed via `tools/gate_0008.mjs`: user read = full count 2, anon = 0 as data, user POST = 403) |

Ten deliberate calls worth recording, because a backtest is the easiest place in this product to
ship a number that is technically correct and materially misleading:

1. **Every fill and exit rule is pessimistic, and each one costs performance.** A fill needs a bar
   that *trades through* the entry and fills at the worse of entry/open; the entry bar cannot also be
   the exit bar; a bar spanning BOTH the stop and the target is a **loss**, because OHLC does not
   record intrabar order and "unknowable" must resolve to the worse outcome; and no exit is invented at
   the end of the series. The same-bar rule is the load-bearing one — resolving it optimistically is
   the classic way a losing system gets reported as a winning one.
2. **A setup that never fills is not a loss.** `ReplayResult.notFilled` exists so the aggregate can
   exclude it from the denominator. Counting it as a loss makes a selective entry look like it missed
   money, which is the most flattering error available to a backtest.
3. **An open position is not a win.** A trade still running when the visible bars run out is
   `unresolved`: it counts as a trade (it existed and held risk) but never as a win, and it is
   labelled `STILL OPEN` rather than presented as a result.
4. **`ReplayScan` refuses to state a rate it cannot support.** Below `minimumTrades` (10, not 5 — a
   scan re-anchors on every bar so neighbouring results are strongly correlated and one trend
   manufactures a dozen apparent "trades") the card prints the sample size and *no rate at all*.
   Same rule, same reason as `LeakDetector` in 2.4. A win rate off three correlated bars is not a weak
   statistic, it is a misleading one.
5. **Profit factor is null, never infinite.** A flawless run has nothing to divide by, and printing
   "∞" beside a backtest invites the reader to treat it as a measured edge.
6. **Every pip and R figure goes through `TradingMath`.** A 0.10 move is 10 pips of gold and 1000 of
   EURUSD; treating them alike is the easiest way to publish a backtest that is off by 100x. The sign
   of R is built from BOTH the price move and the direction — an MAE that comes back positive is
   exactly the bug that makes a risky setup look safe, and the engine test asserts against it.
7. **The mock generates bars, it does not recall them.** `MockPriceBarRepository` runs a seeded walk
   rather than deriving bars from `MockData.trades()`. Inventing bars to agree with a set of trades
   would be a second, hidden claim that those trades happened at those prices. Its output is labelled
   `SYNTHETIC DEMO` on the chart, because an unlabelled generated chart is indistinguishable from the
   market.
8. **A cached series states its age; a generated one states it is not the market.** Provenance lives on
   the data (`PriceSeriesSource`) and is rendered beside the chart, so there is no path to a chart
   that does not say where its bars came from.
9. **The cursor only ever reveals a prefix.** `visibleBarsProvider` slices the series, so a bar the
   trader has not stepped to cannot influence the verdict printed beside the chart. That is what makes
   this a replay rather than a static report, and it is structural rather than a thing to remember.
10. **`TWELVEDATA_KEY` never reaches the device, and no client may write the cache.** A
    `--dart-define` key ships inside the APK, where an installer can extract it and spend our metered
    allowance from outside the product. So the fetch is server-side only, the symbol is an ALLOWLIST
    (not a blacklist — an open field would let any signed-in user bill us arbitrary instruments), and
    migration 0008 revokes every client write to `prices_cache`. That closes a cross-tenant poisoning
    route which would otherwise let a user POST bars that every other trader's backtest then charts.

## Phase 3 — Signals + Copy

| # | Task | Status |
|---|---|---|
| 3.1 | Signals feed + stats | ✅ repository-backed feed (`SignalRepository` + `signalFeedProvider`: live `signals` table / offline seed), verified ledger (`SignalStats`: win rate withheld below 10 closed calls, open calls never results, cancelled never counted), loading/empty/error states, LIVE/OFFLINE DEMO badges |
| 3.2 | Volatility radar | ✅ pure `VolatilityScore` (two 14-bar true-range windows → expansion + position components → banded 0–100, zero-baseline/NaN guards, null below 29 bars), attached to `SignalStats.volatility` via `withVolatility` (ledger untouched), `signalRadarBarsProvider` reuses the replay bar read (one fetch serves both screens), radar section on `SignalStatsCard` with measuring/error/too-short/stale states + provenance (`SYNTHETIC DEMO`/`CACHED`), hardcoded score-64 card with invented newswire drivers deleted |
| 3.3 | AI chart analysis | ✅ mock-first `ChartAnalysis` (levels 6 / tp 3 / note 400 caps, bias fallback to neutral) + `ai-analyze-chart` Edge Function (JWT caller, ownership prefix, temp Storage read + delete, `gpt-4o-mini`) + screen at `/tools/chart-analysis` with result sheet + risk disclaimer |
| 3.4 | Copy confirm sheet + lots math | ✅ `CopyConfirmSheet` rebuilt to S8: multi-account picker seeded once from the guard selection (local state — picking a copy target never moves the guard's account), risk slider 0.25–5.00% default 1% = server clamp band, per-account lots/max-loss/pip-value preview via pure `CopyPreview.of` (client-knowable half of `evaluateAccount`: inactive → invalid → maxLots, refused size reported not clamped), `CopySettings` Dart mirror of `DEFAULT_SETTINGS` + `clampRiskPct`, paper pill, verbatim `AppStrings.riskDisclaimer`, confirm → paper-toast that says nothing went to a broker; refusal reasons keep their exact `Refusal` names for 1:1 mapping in 3.5; parity fixtures identical to `copy_signal_test.ts` in `test/copy_policy_test.dart` + 5 sheet widget tests; Signals' stale "AI unlocks in Phase 3" button now routes to `/tools/chart-analysis` |
| 3.5 | copy-signal edge (paper default) | ✅ Paper-only client seam: `CopySignalRepository` (Supabase `functions.invoke('copy-signal')` + mock stub with seeded equity), refusal mapping 1:1 (`CopyRefusal.values.byName`), safe error handling (`CopySignalFailure` trader wording, never raw server text), HTTP-status classifier + batch-error mapper, `countOpenFollows` scoped to caller (RLS `own follows` ↔ server JWT filter — same rows) for the preview's `maxConcurrent` prediction; server recomputes lots from server-side equity and recounts at request time, so a stale count costs a preview, never a placement |
| 3.6 | Live copy consent + kill switch | ✅ `CopySettingsRepository` (Supabase own-row RLS read/upsert + mock in-memory row, absent row == `DEFAULT_SETTINGS` on both sides) with `CopySettings` Dart mirror (liveConsent/killSwitch/maxLots 5.0/maxConcurrent 5, risk band 0.25–5.00% default 1%, 10-account cap) wired through `Services` + `copySettingsProvider` (pessimistic saves, one generic save-error line); per-account `copy_enabled` toggle on `TradingAccount` + `AccountRepository.setCopyEnabled` (Supabase + mock, OFF by default → `accountDisabled`); `CopyPreview.of` ladder mirrors `evaluateAccount` order for every client-knowable rule (kill switch → ownership gap (`accountMissing` server-only, mapped but never predicted) → signal validity → `copy_enabled` → live consent → sizing → lot cap (refused size reported) → broker link (live-only) → concurrent cap via `openFollowsProvider`) with 1:1 `CopyRefusal` names; no master/slave routing — each account evaluated independently in request order |

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
