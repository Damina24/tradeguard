import '../../../core/models/account.dart';
import '../../../core/models/copy_settings.dart';
import '../../../core/models/signal.dart';
import '../../../core/utils/trading_math.dart';

/// Why one account's follow cannot be placed. The client's copy of the
/// server's `Refusal` closed set (shared.ts) — the names are kept identical
/// so a refusal from a real `copy-signal` response maps 1:1 with no
/// translation table.
///
/// Since task 3.6 the client holds nearly every fact behind these names:
/// `copy_settings` (kill switch, consent, caps) arrives through
/// `copySettingsProvider`, `copy_enabled` rides on [TradingAccount], and the
/// open-follow count comes from `openFollowsProvider`, so [CopyPreview.of]
/// predicts them before the round trip. The one name it never predicts is
/// [accountMissing]: the picker only ever lists the trader's own RLS-scoped
/// accounts, so the client cannot construct the ownership miss the server
/// guards against — and guessing at it would mean pretending to know whose
/// account an id belongs to.
enum CopyRefusal {
  /// `copy_settings.kill_switch` is ON — blocks every follow before any other
  /// rule is considered, paper included (mirrors shared.ts line 266).
  killSwitch,

  /// Mode `live` without stored `copy_settings.live_consent` — refused, never
  /// silently downgraded to paper (mirrors shared.ts line 277).
  consentRequired,

  /// `broker_accounts.copy_enabled` is OFF for this account — mirrors
  /// `accountDisabled` (shared.ts line 276).
  accountDisabled,

  /// The requested id is not one of the caller's accounts — server-only
  /// (ownership is decided under the verified JWT); the client's preview
  /// never produces it, the toast still maps it if the server does.
  accountMissing,

  /// `openFollows >= settings.max_concurrent_follows` — mirrors
  /// `maxConcurrent` (shared.ts line 294). Predicted against the count the
  /// client fetched; the server recounts, so this prediction can be stale
  /// but never authoritative.
  maxConcurrent,

  /// Mode `live` with no `metaapi_account_id` stored — mirrors
  /// `noMetaapiLink` (shared.ts line 291). Live-only, like the server's rule.
  noMetaapiLink,

  /// Signal not `active` (closed/cancelled) — mirrors `inactiveSignal`.
  inactiveSignal,

  /// Zero-width stop, or nothing to size from — mirrors `invalidSignal`.
  invalidSignal,

  /// Sized over `settings.maxLots` — mirrors `maxLots`. The refused size is
  /// carried so the sheet can say WHY (the server reports it for the same
  /// reason). Refused, never clamped.
  maxLots,
}

/// The preview for ONE account: what `copy-signal` would size for this
/// signal on this account's equity at this risk %.
///
/// A pure function of its inputs (`CopyPreview.of`) so the sheet stays a
/// renderer and the numbers are unit-testable without a widget tree. Since
/// task 3.6 the ladder mirrors `evaluateAccount` for every rule the client
/// holds a fact for — kill switch, signal validity, per-account permission,
/// live consent, sizing, lot cap, broker link, concurrent cap — in the
/// server's own order, with the server's own refusal names. The Edge
/// Function still recomputes lots from server-side equity and re-runs every
/// rule, so this preview is a preview, never an authorization: it can be
/// stale (equity moved, a follow closed), it can never be wrong about what
/// the server is allowed to do.
class CopyPreview {
  const CopyPreview({
    required this.accountId,
    required this.riskPips,
    required this.lots,
    required this.maxLoss,
    this.refusal,
  });

  /// The client's half of `evaluateAccount` (shared.ts lines 266–298): same
  /// check order, same refusal names, inputs the client actually holds.
  ///
  /// [mode] defaults to `'paper'` — the only mode the confirm sheet sends
  /// (task 3.5 contract; a live ask without stored consent is a refusal, never
  /// a downgrade) — but `'live'` is accepted so the two live-only rules
  /// (consent, broker link) stay mirrored and unit-testable against the same
  /// fixtures as `copy_signal_test.ts`. [openFollows] is the count fetched
  /// for this sheet; the server recounts per placement, so a stale count can
  /// only move a refusal between preview and toast — never create a
  /// placement the server did not authorize.
  ///
  /// The one rule NOT mirrored is `accountMissing` (ownership): see
  /// [CopyRefusal.accountMissing].
  static CopyPreview of({
    required Signal signal,
    required TradingAccount account,
    required double riskPct,
    CopySettings settings = CopySettings.defaults,
    String mode = 'paper',
    int openFollows = 0,
  }) {
    final bool live = mode == 'live';

    // 1. Kill switch — blocks everything before any other rule is even
    //    considered, paper included (shared.ts:266). Nothing is sized: when
    //    the switch is on there is no size worth printing.
    if (settings.killSwitch) {
      return CopyPreview(
        accountId: account.id,
        riskPips: 0,
        lots: 0,
        maxLoss: 0,
        refusal: CopyRefusal.killSwitch,
      );
    }

    // 2. (accountMissing — ownership is server-decided; the picker only
    //    lists the trader's own accounts, so there is nothing to predict.)

    // 3. Inactive signals are refused before any sizing, exactly as
    //    server-side: a closed signal is not copyable no matter how healthy
    //    the account is.
    if (signal.status != SignalStatus.active) {
      return CopyPreview(
        accountId: account.id,
        riskPips: 0,
        lots: 0,
        maxLoss: 0,
        refusal: CopyRefusal.inactiveSignal,
      );
    }

    final double riskPips = TradingMath.pipsBetween(
      signal.pair,
      signal.entry,
      signal.stop,
    );
    // 4. entry == stop (or unreadable prices): the stop is zero-width and any
    //    size is a coin flip with unlimited loss. Refused rather than "sized at
    //    maximum" — TradingMath.lotSize returns 0, but the refusal is the point.
    if (!riskPips.isFinite || riskPips <= 0) {
      return CopyPreview(
        accountId: account.id,
        riskPips: 0,
        lots: 0,
        maxLoss: 0,
        refusal: CopyRefusal.invalidSignal,
      );
    }

    // 5. Per-account permission (shared.ts:276): `copy_enabled` is OFF by
    //    default on a freshly connected account, so the refusal is named
    //    before sizing — a disabled account has no size to show.
    if (!account.copyEnabled) {
      return CopyPreview(
        accountId: account.id,
        riskPips: riskPips,
        lots: 0,
        maxLoss: 0,
        refusal: CopyRefusal.accountDisabled,
      );
    }

    // 6. Live consent (shared.ts:277): a live ask without the stored row is
    //    refused — never silently answered as paper, which would make the
    //    trader believe an order reached a broker.
    if (live && !settings.liveConsent) {
      return CopyPreview(
        accountId: account.id,
        riskPips: riskPips,
        lots: 0,
        maxLoss: 0,
        refusal: CopyRefusal.consentRequired,
      );
    }

    final double lots = TradingMath.lotSize(
      balance: account.equity,
      riskPct: riskPct,
      symbol: signal.pair,
      stopPips: riskPips,
    );
    // 7. Zero equity sizes to zero: nothing to risk. The server classifies the
    //    same fact as `invalidSignal`.
    if (lots <= 0) {
      return CopyPreview(
        accountId: account.id,
        riskPips: riskPips,
        lots: 0,
        maxLoss: 0,
        refusal: CopyRefusal.invalidSignal,
      );
    }

    final double maxLoss = TradingMath.riskAmount(
      symbol: signal.pair,
      stopPips: riskPips,
      lots: lots,
    );

    // 8. The stored cap, not the default one (shared.ts:286). Refused, not
    //    clamped: the sheet showed an exact size, and a position at a size
    //    the trader never reviewed is what the cap exists to stop. This is
    //    the only refusal that carries its size — the sheet reports it.
    if (lots > settings.maxLots) {
      return CopyPreview(
        accountId: account.id,
        riskPips: riskPips,
        lots: lots,
        maxLoss: maxLoss,
        refusal: CopyRefusal.maxLots,
      );
    }

    // 9. Live needs the opaque broker link the connect flow stored
    //    (shared.ts:291). Client-knowable from the account row itself.
    if (live && (account.metaapiAccountId ?? '').isEmpty) {
      return CopyPreview(
        accountId: account.id,
        riskPips: riskPips,
        lots: 0,
        maxLoss: 0,
        refusal: CopyRefusal.noMetaapiLink,
      );
    }

    // 10. Concurrent cap (shared.ts:294) against the count fetched for this
    //     sheet. Refused with no size, like every refusal but `maxLots`:
    //     the server's result row reports `lots: 0` for it too.
    if (openFollows >= settings.maxConcurrentFollows) {
      return CopyPreview(
        accountId: account.id,
        riskPips: riskPips,
        lots: 0,
        maxLoss: 0,
        refusal: CopyRefusal.maxConcurrent,
      );
    }

    return CopyPreview(
      accountId: account.id,
      riskPips: riskPips,
      lots: lots,
      maxLoss: maxLoss,
    );
  }

  /// The account this preview sizes for.
  final String accountId;

  /// Stop distance in pips, 0 when the signal cannot be sized.
  final double riskPips;

  /// 2dp lots. Carried even when refused (`maxLots`) so the sheet can report
  /// the refused size; 0 for every other refusal, so a refused preview never
  /// carries a positive size except the one that is reported on purpose.
  final double lots;

  /// Currency lost at the stop for [lots] — the rounded size a broker would
  /// receive, not the unrounded intent, so the number is what is actually
  /// at risk.
  final double maxLoss;

  /// Null when placeable client-side. Server-only rules are re-checked by
  /// the Edge Function and can still refuse this preview.
  final CopyRefusal? refusal;

  bool get isPlaceable => refusal == null;
}