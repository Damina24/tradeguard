import '../../../core/models/trade.dart';
import '../../../core/utils/trading_math.dart';

/// Deterministic facts derived from one trade.
///
/// Strictly a *view* over a [Trade] — nothing is cached and nothing is stored. Every value is a
/// pure function of the persisted row, so grading the same trade twice can never disagree.
///
/// The important rule here: [netPnl] is the PERSISTED `trades.pnl`, copied verbatim. Task 2.1
/// writes it as `profit + commission + swap` and Task 2.2's sync writes the same, so recomputing
/// it in the UI would risk the client disagreeing with the server about a trader's equity.
class TradeMetrics {
  const TradeMetrics({
    required this.trade,
    required this.netPnl,
    required this.rMultiple,
    required this.pipsMoved,
    required this.heldFor,
  });

  /// Builds the metrics for [trade]. Pure and total — any trade, however sparse, yields metrics
  /// with nulls rather than throwing.
  factory TradeMetrics.of(Trade trade) {
    final double? entry = trade.entry;
    final double? exit = trade.exit;
    final double? stop = trade.stop;

    final double? riskPips = (entry != null && stop != null)
        ? TradingMath.pipsBetween(trade.symbol, entry, stop)
        : null;
    final double? riskMoney = riskPips == null
        ? null
        : TradingMath.riskAmount(
            symbol: trade.symbol,
            stopPips: riskPips,
            lots: trade.lots,
          );

    // R multiple needs both a known risk and a non-zero one; a stop exactly on entry is a
    // degenerate export, not a 100R win.
    //
    // Rounded to 2dp — the precision it is displayed at. Without this, floating point can make
    // an exact 1R trade evaluate to 0.9999999999999991 and be graded "under 1R" while the reason
    // beside it reads "+1.00R". Comparisons and display must never disagree.
    final double? r = (riskMoney == null || riskMoney <= 0)
        ? null
        : _round2(trade.pnl / riskMoney);

    return TradeMetrics(
      trade: trade,
      netPnl: trade.pnl,
      rMultiple: r,
      pipsMoved: (entry != null && exit != null)
          ? TradingMath.pipsBetween(trade.symbol, entry, exit)
          : null,
      heldFor: _duration(trade),
    );
  }

  final Trade trade;

  /// The persisted, authoritative result. Never recomputed.
  final double netPnl;

  /// Result in units of initial risk. Null when the export carried no usable stop.
  final double? rMultiple;

  /// Absolute price movement in pips, direction-agnostic.
  final double? pipsMoved;

  /// Open→close duration, or null if either timestamp is missing.
  final Duration? heldFor;

  bool get isWin => netPnl > 0;

  /// Break-even after costs. Exposed as a state rather than a colour so the UI can label it.
  bool get isBreakeven => netPnl == 0;

  /// A loss bigger than 1R — the trade that actually hurt the account.
  bool get isBigLoss => !isWin && (rMultiple != null && rMultiple! <= -1);

  /// Costs charged on this trade. Read from the persisted columns, not recomputed.
  double get costs => trade.commission + trade.swap;

  static Duration? _duration(Trade t) {
    final DateTime? open = t.openTime;
    final DateTime? close = t.closeTime;
    if (open == null || close == null) return null;
    final Duration d = close.difference(open);
    // A broker that restates a timestamp can produce a negative hold; clamp rather than show "-3h".
    return d.isNegative ? Duration.zero : d;
  }

  static double _round2(double v) => double.parse(v.toStringAsFixed(2));
}