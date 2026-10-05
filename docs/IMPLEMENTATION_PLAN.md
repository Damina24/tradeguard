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
