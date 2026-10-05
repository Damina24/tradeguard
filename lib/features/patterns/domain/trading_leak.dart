import '../../../core/utils/formatters.dart';
import 'leak_thresholds.dart';
import 'pattern_dimension.dart';

/// What kind of recurring weakness a [TradingLeak] describes.
///
/// Both kinds are defined purely in terms of what `v_patterns` exposes. Nothing
/// here reads psychology, "discipline" or "emotion" — the app holds no data of
/// that kind, and inventing it would be advice dressed up as analytics.
enum LeakKind {
  /// A slice (one symbol, session, hour or weekday) that is net negative across
  /// a meaningful number of trades. This is the roadmap's "best hour / day /
  /// setup / session leaks" and the store copy's "the hour, session, symbol or
  /// setup that quietly drains your edge".
  netNegativeSlice('slice'),

  /// A slice accounting for an outsized share of all the trader's losses, even
  /// where the rest of the journal is positive. Losing trades are spread thinly
  /// across many slices, so the concentration is the finding — not any single
  /// loss.
  lossConcentration('concentration');

  const LeakKind(this.label);

  /// Short noun for the evidence line.
  final String label;
}

/// How much weight the sample behind a leak can support.
///
/// The point of this enum is honesty: leaks are never reported at one flat level
/// of confidence. The screen renders this as a word beside the leak, never as
/// colour alone.
enum LeakConfidence {
  /// Below the minimum useful sample. The claim is withheld entirely — a thin
  /// sample is not shown with a caveat, it is not shown at all.
  tooSmall,

  /// Enough trades to notice, not enough to lean on.
  low,

  /// A sample worth acting on cautiously.
  moderate,

  /// A long history behind the claim.
  high;

  /// Trader-facing wording. Never empty, so the UI always has a label to render.
  String get label => switch (this) {
        LeakConfidence.tooSmall => 'Too few trades',
        LeakConfidence.low => 'Small sample',
        LeakConfidence.moderate => 'Moderate sample',
        LeakConfidence.high => 'Large sample',
      };

  /// The sentence shown under the evidence.
  String get caveat => switch (this) {
        LeakConfidence.tooSmall =>
          'Not enough trades here to call this a pattern.',
        LeakConfidence.low =>
          'Based on a small number of trades. Worth watching rather than '
              'acting on.',
        LeakConfidence.moderate =>
          'Based on a moderate number of trades. An observation to check, not a '
              'cause.',
        LeakConfidence.high =>
          'Based on a long run of trades. Still an observation, not a proven '
              'cause.',
      };

  /// Maps a trade count onto a confidence level.
  ///
  /// Thresholds are the same ones [LeakThresholds] gates reporting on, so the
  /// label can never claim more confidence than the detector granted.
  static LeakConfidence fromTrades(int trades, LeakThresholds thresholds) {
    if (trades < thresholds.minTrades) return LeakConfidence.tooSmall;
    if (trades < thresholds.moderateTrades) return LeakConfidence.low;
    if (trades < thresholds.highTrades) return LeakConfidence.moderate;
    return LeakConfidence.high;
  }
}

/// A repeatable, evidenced weakness in the trader's own results.
///
/// Deliberately narrow: a leak is NOT "a losing trade" and NOT a forecast. It is
/// an observation that recurs across a stated number of trades, with the numbers
/// attached so the trader can check the reasoning and disagree with it.
class TradingLeak {
  const TradingLeak({
    required this.kind,
    required this.dimension,
    required this.label,
    required this.pnl,
    required this.trades,
    required this.winRate,
    required this.title,
    required this.evidence,
    required this.recommendation,
    required this.confidence,
  });

  final LeakKind kind;

  /// Which column of `v_patterns` this was found on.
  final PatternDimension dimension;

  /// The slice's display name — `'London'`, `'14:00'`, `'XAUUSD'`, `'Tuesday'`.
  final String label;

  /// Net P&L of the slice, straight from the view.
  final double pnl;

  /// How many trades the claim rests on. Always shown: a leak backed by two
  /// trades is an anecdote, and the UI must not dress it up as a pattern.
  final int trades;

  /// Win rate of the slice, straight from the view.
  final double winRate;

  /// One line naming the finding, e.g. "London trades are net negative".
  final String title;

  /// The numbers behind [title], already formatted for display.
  final List<String> evidence;

  /// What to look at next. Always hedged: the app is not an adviser and must not
  /// issue a trading instruction off a sample of trades.
  final String recommendation;

  /// How much weight [trades] supports. Rendered as a word, not a colour.
  final LeakConfidence confidence;

  /// Result per trade, or null when the count is zero.
  double? get expectancy => trades <= 0 ? null : pnl / trades;

  @override
  String toString() =>
      'TradingLeak(${kind.name} ${dimension.name}:$label n=$trades pnl=$pnl)';
}

/// What a leak sweep found.
///
/// [leaks] empty is a legitimate, displayed outcome — "nothing qualified" is
/// information, and the screen says so rather than showing an empty box.
class LeakReport {
  const LeakReport({
    required this.leaks,
    required this.sampleTrades,
    required this.minimumTrades,
    required this.reviewedSlices,
  });

  /// An empty report, for the loading / empty / error states.
  factory LeakReport.empty({int minimumTrades = 5, int sampleTrades = 0}) =>
      LeakReport(
        leaks: const <TradingLeak>[],
        sampleTrades: sampleTrades,
        minimumTrades: minimumTrades,
        reviewedSlices: 0,
      );

  /// Findings, worst net result first.
  final List<TradingLeak> leaks;

  /// Total trades across the journal as the view reported them.
  final int sampleTrades;

  /// The gate below which nothing is reported.
  final int minimumTrades;

  /// Slices examined across every dimension, so the screen can show the sweep
  /// happened even when it found nothing.
  final int reviewedSlices;

  bool get isEmpty => leaks.isEmpty;

  /// Trades exist, just not enough to judge anything by.
  ///
  /// Kept distinct from "no trades at all": those two need different words and
  /// different next actions, and merging them would tell a brand-new trader they
  /// have no leaks when they have no data.
  bool get isInsufficient => sampleTrades > 0 && sampleTrades < minimumTrades;
}

/// The "n trades / net P&L / win rate" line every leak leads with.
///
/// Lives beside the model rather than in a widget so the same figure reads the
/// same way on the leaks screen, in a pattern row and in a test.
class LeakEvidence {
  LeakEvidence._();

  /// Trade count, net result and hit rate for a slice.
  ///
  /// Takes the three figures rather than a [TradingLeak] so both the detector and
  /// the pattern rows can format the same numbers through one implementation —
  /// the alternative is two copies of this string drifting apart.
  static String summary({
    required int trades,
    required double pnl,
    required double winRate,
  }) {
    final int wins = (winRate * trades).round();
    return '$trades trade${trades == 1 ? '' : 's'} • '
        '${Formatters.signed(pnl)} net • '
        '$wins of $trades won (${(winRate * 100).round()}%)';
  }

  /// The same line for a leak.
  static String forLeak(TradingLeak leak) =>
      summary(trades: leak.trades, pnl: leak.pnl, winRate: leak.winRate);

  /// Expectancy, phrased as an average so a large slice is not mistaken for a
  /// profitable one.
  static String expectancy(double? perTrade) => perTrade == null
      ? 'Average per trade: not available'
      : 'Average per trade: ${Formatters.signed(perTrade)}';
}