import '../../../core/models/trade.dart';
import 'trade_grade.dart';
import 'trade_metrics.dart';

/// One line of the review checklist.
class ReviewReason {
  const ReviewReason({
    required this.passed,
    required this.text,
    this.evidence,
  });

  /// Whether the check was met. Drives the "rule checklist compliance bar" in the design doc.
  final bool passed;

  /// Trader-safe wording. Shown verbatim, so it must never contain a raw error or a credential.
  final String text;

  /// The number behind the verdict, when there is one ("+2.10R").
  final String? evidence;

  bool get isSoft => !passed && evidence != null;
}

/// A trade's grade plus the reasoning that produced it.
///
/// Separation of concerns, deliberately:
///   * raw facts     -> [Trade] (persisted row)
///   * derived facts -> [TradeMetrics] (pure)
///   * verdict       -> this class (pure, deterministic)
///   * wording       -> the UI
///
/// So the same trade always grades the same way, and a test can assert on the reasons rather
/// than on pixels.
class TradeReview {
  const TradeReview({
    required this.metrics,
    required this.grade,
    required this.reasons,
  });

  /// Grades [trade]. Pure, deterministic and side-effect free.
  factory TradeReview.of(TradeMetrics metrics) {
    final Trade t = metrics.trade;
    final double? r = metrics.rMultiple;
    final List<ReviewReason> reasons = <ReviewReason>[];

    // --- Process checks: did the trader plan the trade before taking it? ---
    final bool plannedRisk = t.stop != null;
    reasons.add(ReviewReason(
      passed: plannedRisk,
      text: plannedRisk
          ? 'Stop loss was set, so the risk was known before entry.'
          : 'No stop loss recorded — the risk on this trade was undefined.',
    ),);

    final bool plannedReward = t.target != null;
    reasons.add(ReviewReason(
      passed: plannedReward,
      text: plannedReward
          ? 'A take profit target was set.'
          : 'No take profit recorded — the exit had no plan behind it.',
    ),);

    // --- Outcome checks: use the PERSISTED result, never a recomputed one ---
    reasons.add(ReviewReason(
      passed: metrics.isWin,
      text: metrics.isWin
          ? 'Closed in profit.'
          : metrics.isBreakeven
              ? 'Closed break-even.'
              : 'Closed in loss.',
      evidence: metrics.isBreakeven ? null : _r(r),
    ),);

    // Only meaningful when we could measure risk at all.
    final bool respectedRisk = r == null ? true : r >= -1;
    reasons.add(ReviewReason(
      passed: respectedRisk,
      text: r == null
          ? 'Risk could not be measured (no stop), so loss size was unchecked.'
          : respectedRisk
              ? 'Loss stayed inside the 1R the stop defined.'
              : 'Loss exceeded the 1R the stop defined — the exit was not respected.',
      evidence: r == null ? null : _r(r),
    ),);

    // A >= 1R winner is the one outcome check that is about process as much as luck.
    final bool goodReward = r != null && r >= 1;
    if (r != null) {
      reasons.add(ReviewReason(
        passed: goodReward,
        text: goodReward
            ? 'Result was at least 1R, so the target was met.'
            : 'Result was under 1R, so the reward was not realised.',
        evidence: _r(r),
      ),);
    }

    // --- Cost awareness: the slippage that quietly eats a prop account ---
    // Costs are stored negative, so compare magnitudes: a $1 win that carried $100 of
    // commission did not really win.
    final bool costsReasonable =
        !metrics.isWin || metrics.costs.abs() <= metrics.netPnl;
    reasons.add(ReviewReason(
      passed: costsReasonable,
      text: costsReasonable
          ? 'Commission and swap stayed well inside the result.'
          : 'Commission and swap wiped out the gross profit.',
      evidence: metrics.costs == 0 ? null : metrics.costs.toStringAsFixed(2),
    ),);

    final int passedCount = reasons.where((ReviewReason x) => x.passed).length;
    final bool processOk = plannedRisk && plannedReward;
    final bool outcomeOk = metrics.isWin;

    return TradeReview(
      metrics: metrics,
      grade: _grade(
        passedCount,
        reasons.length,
        processOk,
        outcomeOk,
        goodReward,
      ),
      reasons: reasons,
    );
  }

  final TradeMetrics metrics;

  /// The verdict. Never null — an ungraded trade gets [TradeGrade.c] with reasons explaining
  /// why, which is more useful than hiding the grade until a rule passes.
  final TradeGrade grade;

  final List<ReviewReason> reasons;

  /// Checks met / total, for the compliance bar.
  int get passedCount => reasons.where((ReviewReason r) => r.passed).length;

  int get totalCount => reasons.length;

  double get compliance => totalCount == 0 ? 0 : passedCount / totalCount;

  /// Short headline for the share card and the list row.
  String get headline {
    final double? r = metrics.rMultiple;
    final String rText = r == null ? '—' : '${r >= 0 ? '+' : ''}${r.toStringAsFixed(2)}R';
    return '$rText · ${grade.label}';
  }

  /// Maps the checklist onto the product's A–D vocabulary.
  ///
  /// Deliberately a plain, readable lookup rather than a weighted score: the product spec defines
  /// the four letters but no thresholds, so the simplest defensible rule is used and every input
  /// to it is visible in [reasons]. A trader who disagrees can set A–D by hand — that field
  /// already exists on the row — and a hand-set grade always wins over this.
  /// An A additionally requires the >= 1R target. Without that, a 0.05R scalp that happened to
  /// keep its stop and target would score a perfect checklist and grade A, which is exactly the
  /// kind of flattering nonsense that makes a journal useless.
  static TradeGrade _grade(
    int passed,
    int total,
    bool processOk,
    bool outcomeOk,
    bool rewardMet,
  ) {
    if (total == 0) return TradeGrade.c;
    final double ratio = passed / total;
    if (processOk && outcomeOk && rewardMet && ratio >= 0.8) {
      return TradeGrade.a;
    }
    if (outcomeOk && ratio >= 0.6) return TradeGrade.b;
    if (processOk || outcomeOk) return TradeGrade.c;
    return TradeGrade.d;
  }

  static String _r(double? r) =>
      r == null ? '' : '${r >= 0 ? '+' : ''}${r.toStringAsFixed(2)}R';
}