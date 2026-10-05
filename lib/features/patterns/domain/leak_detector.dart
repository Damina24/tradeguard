import 'leak_thresholds.dart';
import 'pattern_dimension.dart';
import 'pattern_metrics.dart';
import 'pattern_row.dart';
import 'trading_leak.dart';

/// Finds recurring weaknesses in a trader's own results.
///
/// Pure, deterministic and side-effect free: the same rows in produce the same
/// report, in the same order, every time. That matters more here than elsewhere,
/// because a leak list that reshuffles between rebuilds reads as the app guessing.
///
/// Two rules, both derived only from what `v_patterns` projects:
///
///   1. [LeakKind.netNegativeSlice] — a slice whose summed `pnl` is negative once
///      it holds at least `minTrades` trades.
///   2. [LeakKind.lossConcentration] — a slice holding at least `lossShare` of
///      the journal's total net losses, however positive the journal is overall.
///
/// Both are deliberately shallow. Nothing here infers *why* a slice lost: the
/// view carries no execution, stop or emotion data to support such an inference,
/// so recommendations point the trader at their own records rather than telling
/// them what to change.
class LeakDetector {
  const LeakDetector({this.thresholds = const LeakThresholds()});

  /// The bars a finding must clear. Injectable so a test can prove the boundary
  /// is honoured rather than asserting on incidental fixture sizes.
  final LeakThresholds thresholds;

  /// Sweeps every dimension in [metrics].
  LeakReport detect(Iterable<PatternMetrics> metrics) {
    final List<PatternMetrics> sets = metrics.toList(growable: false);
    if (sets.isEmpty) return LeakReport.empty(minimumTrades: thresholds.minTrades);

    // The dimensions are OVERLAPPING views of the same trades — every row appears
    // in all four. So `journalTrades` is taken from ONE set rather than summed
    // across them, which would multiply the trader's result by four.
    final PatternMetrics reference = sets.first;

    int reviewed = 0;
    final List<TradingLeak> found = <TradingLeak>[];

    for (final PatternMetrics set in sets) {
      reviewed += set.metrics.length;

      // Total losses are computed PER DIMENSION, and this matters. The dimensions
      // overlap, so a global total would count the same loss four times and every
      // slice's share would come out at roughly a quarter — which would make the
      // concentration rule unreachable rather than merely strict. Within one
      // dimension the slices are disjoint, so the shares are comparable.
      double losses = 0;
      for (final PatternMetric m in set.metrics) {
        if (m.pnl < 0) losses += -m.pnl;
      }

      for (final PatternMetric m in set.metrics) {
        // Sample gate first: a single losing trade never becomes a leak, however
        // large the loss. Nothing in the spec asks for single-trade warnings.
        if (m.trades < thresholds.minTrades) continue;
        if (m.pnl >= 0) continue;

        final LeakConfidence confidence =
            LeakConfidence.fromTrades(m.trades, thresholds);
        final double share = losses <= 0 ? 0 : (-m.pnl / losses);

        found.add(_sliceLeak(m, confidence, share));
        if (share >= thresholds.lossShare) {
          found.add(_concentrationLeak(m, confidence, share));
        }
      }
    }

    found.sort(_bySeverity);

    return LeakReport(
      leaks: List<TradingLeak>.unmodifiable(found),
      sampleTrades: reference.journalTrades,
      minimumTrades: thresholds.minTrades,
      reviewedSlices: reviewed,
    );
  }

  /// Convenience for callers holding raw [rows]: aggregates them first, so no
  /// caller is tempted to hand-roll the grouping the detector needs.
  LeakReport detectRows(List<PatternRow> rows) =>
      detect(PatternMetrics.allDimensions(rows));

  TradingLeak _sliceLeak(
    PatternMetric m,
    LeakConfidence confidence,
    double share,
  ) {
    final String what = _subject(m);
    return TradingLeak(
      kind: LeakKind.netNegativeSlice,
      dimension: m.dimension,
      label: m.label,
      pnl: m.pnl,
      trades: m.trades,
      winRate: m.winRate,
      title: '$what is net negative',
      evidence: <String>[
        LeakEvidence.summary(trades: m.trades, pnl: m.pnl, winRate: m.winRate),
        LeakEvidence.expectancy(m.expectancy),
        if (share > 0)
          '${(share * 100).round()}% of the net losses in your journal came '
              'from this ${m.dimension.label.toLowerCase()}',
      ],
      recommendation: _recommendation(m, confidence),
      confidence: confidence,
    );
  }

  TradingLeak _concentrationLeak(
    PatternMetric m,
    LeakConfidence confidence,
    double share,
  ) {
    return TradingLeak(
      kind: LeakKind.lossConcentration,
      dimension: m.dimension,
      label: m.label,
      pnl: m.pnl,
      trades: m.trades,
      winRate: m.winRate,
      title: 'Most of your losses sit in ${_subject(m).toLowerCase()}',
      evidence: <String>[
        LeakEvidence.summary(trades: m.trades, pnl: m.pnl, winRate: m.winRate),
        '${(share * 100).round()}% of your total net losses are in this '
            '${m.dimension.label.toLowerCase()}',
      ],
      recommendation: _recommendation(m, confidence),
      confidence: confidence,
    );
  }

  /// The slice described in plain words, e.g. "London session" or "XAUUSD trades".
  ///
  /// The label is used verbatim — it is already display-cased by
  /// [PatternLabels] — rather than lower-cased, because "The london session"
  /// reads as a typo.
  String _subject(PatternMetric m) => switch (m.dimension) {
        PatternDimension.symbol => '${m.label} trades',
        PatternDimension.session => 'The ${m.label} session',
        PatternDimension.hour => 'Trades closed around ${m.label}',
        PatternDimension.dayOfWeek => '${m.label} trades',
      };

  /// Cautious by construction.
  ///
  /// No verdict on cause, no instruction to stop trading something, no promise
  /// that fixing it fixes the account. Every recommendation is a "look at this
  /// first", which is the strongest claim this data supports.
  String _recommendation(PatternMetric m, LeakConfidence confidence) {
    final String where = switch (m.dimension) {
      PatternDimension.symbol => 'these ${m.label} trades',
      PatternDimension.session => 'your ${m.label} session trades',
      PatternDimension.hour => 'the trades you close around ${m.label}',
      PatternDimension.dayOfWeek => 'your ${m.label} trades',
    };
    return switch (confidence) {
      LeakConfidence.low =>
        'Worth keeping an eye on $where. ${confidence.caveat}',
      LeakConfidence.moderate =>
        'Worth reviewing $where in your journal before your next session. This '
            'is an observation across ${m.trades} trades, not a proven cause.',
      LeakConfidence.high =>
        'Worth reviewing $where in your journal. The sample is large, but the '
            'app cannot tell you why it happened — your own notes are the '
            'evidence.',
      LeakConfidence.tooSmall => confidence.caveat,
    };
  }

  /// Worst result first, then the more specific finding, then dimension order,
  /// then label. Total and value-based, so two runs over identical data always
  /// produce identical ordering.
  static int _bySeverity(TradingLeak a, TradingLeak b) {
    final int byPnl = a.pnl.compareTo(b.pnl);
    if (byPnl != 0) return byPnl;
    final int byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind;
    final int byDimension = a.dimension.index.compareTo(b.dimension.index);
    if (byDimension != 0) return byDimension;
    return a.label.compareTo(b.label);
  }
}