import '../../../core/models/account.dart';
import '../../../core/models/copy_settings.dart';
import '../../../core/models/signal.dart';
import '../../../core/utils/trading_math.dart';

/// Why one account's follow cannot be placed. The client-knowable subset of
/// the server's `Refusal` closed set (shared.ts) — the names are kept
/// identical so a refusal from a real `copy-signal` response maps 1:1 with
/// no translation table. The server-only rules (kill switch, live consent,
/// per-account permission, ownership, concurrent cap) are deliberately NOT
/// predicted here: the client does not hold those facts, and guessing them
/// would let a preview disagree with the order that actually runs.
enum CopyRefusal {
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
/// renderer and the numbers are unit-testable without a widget tree. The
/// ladder mirrors `evaluateAccount` for the rules the client can know —
/// signal validity, then size, then the cap — and returns the server's
/// verdict vocabulary for the rest: the Edge Function recomputes lots from
/// server-side equity and re-runs every rule, so this preview is a
/// preview, never an authorization.
class CopyPreview {
  const CopyPreview({
    required this.accountId,
    required this.riskPips,
    required this.lots,
    required this.maxLoss,
    this.refusal,
  });

  /// Mirrors `evaluateAccount` (shared.ts), client-knowable rules only.
  static CopyPreview of({
    required Signal signal,
    required TradingAccount account,
    required double riskPct,
    CopySettings settings = CopySettings.defaults,
  }) {
    // Inactive signals are refused before any sizing, exactly as server-side:
    // a closed signal is not copyable no matter how healthy the account is.
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
    // entry == stop (or unreadable prices): the stop is zero-width and any
    // size is a coin flip with unlimited loss. Refused rather than "sized at
    // maximum" — TradingMath.lotSize returns 0, but the refusal is the point.
    if (!riskPips.isFinite || riskPips <= 0) {
      return CopyPreview(
        accountId: account.id,
        riskPips: 0,
        lots: 0,
        maxLoss: 0,
        refusal: CopyRefusal.invalidSignal,
      );
    }

    final double lots = TradingMath.lotSize(
      balance: account.equity,
      riskPct: riskPct,
      symbol: signal.pair,
      stopPips: riskPips,
    );
    // Zero equity sizes to zero: nothing to risk. The server classifies the
    // same fact as `invalidSignal`.
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

    if (lots > settings.maxLots) {
      // Refused, not clamped: the sheet showed an exact size, and a position
      // at a size the trader never reviewed is what the cap exists to stop.
      return CopyPreview(
        accountId: account.id,
        riskPips: riskPips,
        lots: lots,
        maxLoss: maxLoss,
        refusal: CopyRefusal.maxLots,
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