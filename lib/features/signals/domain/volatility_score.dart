import 'dart:math' as math;

import '../../replay/domain/price_bar.dart';

/// How loud the market has been relative to its OWN recent history.
///
/// A closed set, because the band is what the trader reads first and each
/// word has to mean exactly one thing. The thresholds sit around the neutral
/// 50 a flat series produces by construction, so "calm" always means *quieter
/// than this series usually is* and "high" means *louder than usual* — never
/// an absolute claim about the market.
enum VolatilityBand {
  /// Below 40: ranges compressing versus the baseline window.
  calm('Calm', 0),

  /// 40–59: near the series' own normal.
  moderate('Moderate', 40),

  /// 60–79: ranges widening noticeably.
  elevated('Elevated', 60),

  /// 80–100: ranges far above the baseline — the "think twice" band.
  high('High', 80);

  const VolatilityBand(this.label, this.floor);

  /// Word shown on the radar.
  final String label;

  /// Inclusive score floor. [forScore] walks the values in declaration
  /// order, so the LAST band whose floor the score clears is its band —
  /// which is the highest one, since floors ascend.
  final int floor;

  /// The band a score belongs to. Total over 0…100; values outside are
  /// clamped rather than rejected, because a rounding at the edge must not
  /// crash a screen.
  static VolatilityBand forScore(int score) {
    VolatilityBand result = calm;
    for (final VolatilityBand band in values) {
      if (score >= band.floor) result = band;
    }
    return result;
  }
}

/// A volatility reading over one bar series — pure, deterministic, and
/// deliberately a statement about the PAST.
///
/// The score answers exactly one question: *how do the last [window] bars
/// compare with the [window] before them?* Two true-range windows, one
/// recent and one baseline, combined into a 0…100 number:
///
///   * **Expansion component (60%)** — `50 · (1 + log2(recent/baseline))`,
///     so a doubling of range lands on 100, a halving on 0, and no change on
///     the neutral 50. The ratio is clamped to [minRatio]…[maxRatio] first:
///     a near-zero baseline can produce ratios that are arithmetically true
///     and practically meaningless, and a score that swings to 100 because
///     of one dead bar would be noise dressed as signal.
///   * **Position component (40%)** — where the recent ATR sits between the
///     series' smallest and largest true range. This is what keeps a
///     uniformly wide series from reading as "calm" merely because its own
///     second half was wider still.
///
/// Three properties are deliberate, and each is pinned by a test:
///
///   * **Never NaN, never Infinity.** Every division is guarded (zero
///     baselines, zero price floors), because a NaN rendered on a trading
///     screen is worse than no score at all.
///   * **Order-insensitive at the input edge.** Bars are sorted oldest →
///     newest internally, so a provider handing back newest-first cannot
///     silently compute the comparison backwards. The input list is never
///     mutated.
///   * **Null below [minBars].** Fewer bars than two full windows cannot
///     support a "recent vs baseline" statement; the honest answer is
///     *no score*, which the radar renders as its own state — never as 0,
///     which would read as "market dead calm".
///
/// What this is NOT: a forecast, a risk-free flag, or a claim about future
/// ranges. It describes bar ranges that already printed. The card says so on
/// screen, and the numbers exposed here ([rangePct], [expansionPct]) let the
/// reader check the score instead of trusting it.
class VolatilityScore {
  const VolatilityScore({
    required this.score,
    required this.barCount,
    required this.baselineAtr,
    required this.recentAtr,
    required this.rangePct,
    required this.expansionPct,
  });

  /// True-range bars in EACH window (recent and baseline).
  ///
  /// Fourteen, matching the classic ATR period — short enough to react
  /// within a session, long enough that one spike does not own the reading.
  static const int window = 14;

  /// Bars required before a score may be stated: two full windows of true
  /// range plus the bar that anchors them (`window * 2 + 1` = 29). Below
  /// this, [of] returns null.
  static const int minBars = window * 2 + 1;

  /// Expansion ratios outside this band are treated as the band itself. The
  /// clamp keeps a near-zero baseline from manufacturing an absurd ratio and
  /// makes the displayed [expansionPct] consistent with the number the score
  /// was actually built from.
  static const double minRatio = 0.25;
  static const double maxRatio = 4.0;

  /// Weight of the expansion component in the final score; the position
  /// component takes the remainder. Expansion leads because *change* is what
  /// a "radar" exists to detect — a market that is always wide is normal
  /// for that market, a market that just got wide is the story.
  static const double _expansionWeight = 0.6;

  /// 0…100, rounded to an integer — a score is read, not computed, at a
  /// glance, and '64' beside a band word is honest precision while '63.7'
  /// implies the formula knows more than it does.
  final int score;

  /// Bars the reading was taken over (after malformed bars were dropped).
  final int barCount;

  /// Mean true range of the baseline window, in price units.
  final double baselineAtr;

  /// Mean true range of the recent window, in price units.
  final double recentAtr;

  /// Recent ATR as a percentage of the last close — the one figure that
  /// makes two symbols comparable (0.3% of gold is not 0.3% of EURUSD).
  final double rangePct;

  /// Recent ATR versus baseline, as a signed percentage. Positive means
  /// ranges are widening. Computed from the CLAMPED ratio, so it always
  /// agrees with the number the score used.
  final double expansionPct;

  /// The band this score falls in.
  VolatilityBand get band => VolatilityBand.forScore(score);

  /// Scores the bars, oldest → newest preferred but not required.
  ///
  /// Returns null — not a score of 0 — when the series cannot support the
  /// statement: empty, too short after malformed bars are dropped, or with
  /// no finite prices to measure. `0` would read as "market dead calm";
  /// `null` reads as "not measured", which is what is true.
  static VolatilityScore? of(List<PriceBar> bars) {
    // Defensive copy + sort: the caller's list is never mutated, and a
    // newest-first provider cannot flip the recent/baseline comparison.
    final List<PriceBar> sorted = List<PriceBar>.of(bars)
      ..sort((PriceBar a, PriceBar b) => a.time.compareTo(b.time));

    // A malformed bar (NaN price, high below low) is dropped rather than
    // thrown on — one bad row must not cost the trader the whole reading —
    // but what remains must still clear the window floor.
    final List<PriceBar> usable =
        sorted.where((PriceBar b) => b.isWellFormed).toList(growable: false);
    if (usable.length < minBars) return null;

    // True range for every bar after the first: the widest of the bar's own
    // range and its gaps from the previous close. The first bar has no
    // previous close, so it contributes no true range — which is exactly why
    // [minBars] counts one extra bar.
    final List<double> trueRanges = List<double>.filled(usable.length - 1, 0);
    for (int i = 1; i < usable.length; i++) {
      final PriceBar bar = usable[i];
      final double prevClose = usable[i - 1].close;
      trueRanges[i - 1] = math.max(
        bar.high - bar.low,
        math.max((bar.high - prevClose).abs(), (bar.low - prevClose).abs()),
      );
    }

    final double baselineAtr = _mean(trueRanges, 0, window);
    final double recentAtr =
        _mean(trueRanges, trueRanges.length - window, window);

    // Expansion, guarded: an all-flat baseline divides by zero, and
    // "0/0 → neutral, positive/0 → maximum" is the only reading that lies
    // least about a series that never moved versus one that just started.
    final double ratio = _ratio(baselineAtr, recentAtr);

    // Expansion component: log2 so doubling and halving are symmetric
    // around the neutral 50, then clamped so the guards above can neither
    // overspill 0…100 nor land below it.
    double expansion = 50 * (1 + math.log(ratio) / math.ln2);
    if (expansion < 0) expansion = 0;
    if (expansion > 100) expansion = 100;

    // Position component: where the recent ATR sits between the series'
    // quietest and loudest true range. A uniform series (min == max) is
    // genuinely neutral, so it scores the midpoint rather than dividing by
    // zero.
    double minTr = trueRanges.first;
    double maxTr = trueRanges.first;
    for (final double tr in trueRanges) {
      if (tr < minTr) minTr = tr;
      if (tr > maxTr) maxTr = tr;
    }
    final double spread = maxTr - minTr;
    final double position = spread <= 0 ? 0.5 : (recentAtr - minTr) / spread;
    final double positionComponent = position * 100;

    final double combined = _expansionWeight * expansion +
        (1 - _expansionWeight) * positionComponent;
    final int score = combined.round().clamp(0, 100);

    final double lastClose = usable.last.close;
    final double rangePct =
        lastClose > 0 ? (recentAtr / lastClose) * 100 : 0.0;

    return VolatilityScore(
      score: score,
      barCount: usable.length,
      baselineAtr: baselineAtr,
      recentAtr: recentAtr,
      rangePct: rangePct,
      expansionPct: (ratio - 1) * 100,
    );
  }

  /// Mean of [count] values starting at [start]. Caller guarantees the
  /// bounds — an empty window would be a logic error, not a condition the
  /// market can produce.
  static double _mean(List<double> values, int start, int count) {
    double sum = 0;
    for (int i = start; i < start + count; i++) {
      sum += values[i];
    }
    return sum / count;
  }

  /// recent / baseline, clamped to [minRatio]…[maxRatio].
  ///
  /// A zero baseline with zero recent range reads as 1.0 (no change — the
  /// neutral answer for a series that never moved); a zero baseline with any
  /// recent range reads as the maximum, because "was flat, now moving" is
  /// maximal expansion by any honest reading.
  static double _ratio(double baselineAtr, double recentAtr) {
    double ratio;
    if (baselineAtr <= 0) {
      ratio = recentAtr <= 0 ? 1.0 : maxRatio;
    } else {
      ratio = recentAtr / baselineAtr;
    }
    if (ratio < minRatio) ratio = minRatio;
    if (ratio > maxRatio) ratio = maxRatio;
    return ratio;
  }

  @override
  String toString() => 'VolatilityScore(score=$score, band=$band, '
      'bars=$barCount, rangePct=$rangePct, expansionPct=$expansionPct)';
}
