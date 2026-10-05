import 'pattern_dimension.dart';
import 'pattern_row.dart';

/// One grouped behaviour: "these trades, taken together, looked like this".
///
/// Every figure is derived from SQL's own aggregates in [PatternRow] — this class
/// only *recombines* them (summing sums, weighting averages by their own count).
/// It never reaches back to raw `trades`, so there is exactly one place where a
/// pattern number is defined.
///
/// Two facts are deliberately absent, and the UI must say so rather than fill
/// them in:
///   * **R multiple** and **costs** are not projected by `v_patterns`. R lives
///     on `trades.r_multiple` and costs on `trades.commission/swap`, neither of
///     which the view aggregates. They stay on the per-trade and per-journal
///     stats paths that already own them.
///   * **Grade** is a hand-set A–D letter on `trades.grade` and is likewise not
///     in the view, so no grade distribution is invented here. Grading remains
///     the job of `TradeReview` (task 2.3).
class PatternMetric {
  const PatternMetric({
    required this.dimension,
    required this.value,
    required this.label,
    required this.pnl,
    required this.trades,
    required this.winRate,
  });

  /// Which column of the view this slice came from.
  final PatternDimension dimension;

  /// Raw key as SQL returned it (e.g. `'london'`, `14`, `2`). Null for a group
  /// the trader never populated.
  final Object? value;

  /// Trader-facing name for [value], resolved by [PatternLabels].
  final String label;

  /// Sum of `v_patterns.pnl` across the group. Already net of costs.
  final double pnl;

  /// Sum of `v_patterns.n` across the group.
  final int trades;

  /// Weighted mean of `v_patterns.win_rate`, weighted by each row's own `n`.
  final double winRate;

  /// Average result per trade, from the view's own sum and count.
  ///
  /// Null only when [trades] is zero, which SQL cannot produce — so in practice
  /// this is always populated, and the null path exists for hand-built rows in
  /// tests rather than to paper over a divide-by-zero.
  double? get expectancy => trades <= 0 ? null : pnl / trades;

  bool get isNetNegative => pnl < 0;

  @override
  String toString() => 'PatternMetric(${dimension.label}: $label, '
      'n=$trades, pnl=$pnl, win=$winRate)';
}

/// Pattern metrics for one [PatternDimension], over the signed-in trader's rows.
///
/// Produced by [PatternMetrics.fromRows]. Pure, deterministic, and total: an
/// empty input yields an empty result rather than throwing, because "you have no
/// trades" is a state the UI must render, not an error.
class PatternMetrics {
  const PatternMetrics({
    required this.dimension,
    required this.metrics,
    required this.journalTrades,
    required this.journalPnl,
    required this.droppedRows,
  });

  /// The empty set, used for the no-trades and error states.
  factory PatternMetrics.empty(PatternDimension dimension) => PatternMetrics(
        dimension: dimension,
        metrics: const <PatternMetric>[],
        journalTrades: 0,
        journalPnl: 0,
        droppedRows: 0,
      );

  /// Regroups [rows] along [dimension].
  ///
  /// [droppedRows] counts rows that could not be placed on this dimension — a
  /// `null` hour, say, because the trade had no `close_time`. They are surfaced
  /// instead of being quietly absorbed, because a trader whose pattern looks thin
  /// may simply have trades without close timestamps.
  factory PatternMetrics.fromRows(
    List<PatternRow> rows,
    PatternDimension dimension,
  ) {
    final Map<String, _Bucket> buckets = <String, _Bucket>{};
    int trades = 0;
    double pnl = 0;
    int dropped = 0;

    for (final PatternRow row in rows) {
      final Object? value = _valueOf(row, dimension);
      if (value == null) {
        dropped++;
        continue;
      }
      // A null session groups rather than drops (see `_valueOf`), and it needs a
      // key that cannot collide with a real session name.
      final String key = value is String ? 'null:$value' : 'v:$value';
      buckets
          .putIfAbsent(key, () => _Bucket(value, _labelFor(dimension, value)))
          .add(row);
      trades += row.trades;
      pnl += row.pnl;
    }

    final List<PatternMetric> out = buckets.values
        .map(
          (_Bucket b) => PatternMetric(
            dimension: dimension,
            value: b.value,
            label: b.label,
            pnl: b.pnl,
            trades: b.trades,
            winRate: b.trades <= 0 ? 0 : b.winWeighted / b.trades,
          ),
        )
        .toList()
      ..sort(_byNetPnlThenLabel);

    return PatternMetrics(
      dimension: dimension,
      metrics: List<PatternMetric>.unmodifiable(out),
      journalTrades: trades,
      journalPnl: pnl,
      droppedRows: dropped,
    );
  }

  final PatternDimension dimension;

  /// One entry per distinct value seen, best net result first.
  final List<PatternMetric> metrics;

  /// Total trades behind every metric here — the honest sample size.
  final int journalTrades;

  /// Total net P&L behind every metric here.
  final double journalPnl;

  /// Rows that carried no value for this dimension.
  final int droppedRows;

  bool get isEmpty => metrics.isEmpty;

  /// The slice with the best net result.
  PatternMetric? get best => metrics.isEmpty ? null : metrics.first;

  /// The slice with the most negative result — the first thing worth looking at.
  PatternMetric? get worst => metrics.isEmpty ? null : metrics.last;

  /// Total trades across every metric, i.e. the trader's whole journal as the
  /// view sees it.
  int get totalTrades =>
      metrics.fold<int>(0, (int s, PatternMetric m) => s + m.trades);

  /// Every dimension the view supports, in display order. Used by the screen and
  /// by [LeakDetector], which sweeps all of them.
  static List<PatternMetrics> allDimensions(List<PatternRow> rows) =>
      PatternDimension.values
          .map((PatternDimension d) => PatternMetrics.fromRows(rows, d))
          .toList(growable: false);

  /// The key this row files under on [dimension], or null when it cannot be
  /// placed at all.
  ///
  /// The three cases are deliberately different:
  ///   * a **null session** returns `''` and GROUPS, because `trades.session` is
  ///     nullable and untagged trades are real trades. Dropping them would shrink
  ///     the trader's own sample size without saying so;
  ///   * a **null hour or weekday** returns null and is DROPPED, because it means
  ///     the trade has no `close_time` — it genuinely does not belong to any hour,
  ///     and counting it somewhere would be a fabrication;
  ///   * a **null symbol** returns null and is dropped, since `trades.symbol` is
  ///     NOT NULL and a row without one violates the schema.
  static Object? _valueOf(PatternRow row, PatternDimension dimension) =>
      switch (dimension) {
        PatternDimension.symbol => row.symbol,
        PatternDimension.session => row.session ?? '',
        PatternDimension.hour => row.hour,
        PatternDimension.dayOfWeek => row.dayOfWeek,
      };

  static String _labelFor(PatternDimension dimension, Object? value) =>
      switch (dimension) {
        PatternDimension.symbol => PatternLabels.symbol(value as String?),
        PatternDimension.session =>
          PatternLabels.session(value is String && value.isEmpty ? null : value as String?),
        PatternDimension.hour =>
          PatternLabels.hour(value == null ? -1 : _asInt(value)),
        PatternDimension.dayOfWeek =>
          PatternLabels.dayOfWeek(value == null ? -1 : _asInt(value)),
      };

  static int _asInt(Object v) => v is int ? v : int.parse('$v');

  /// Sorts a copy of [metrics] by [sort]/[direction] without mutating the input.
  ///
  /// Lives here so ranking is testable domain behaviour rather than a `sort`
  /// closure buried in a widget, and so the pattern list and the leaks list cannot
  /// end up using different comparators.
  ///
  /// Every comparator has a label tie-break, which is what makes repeated builds
  /// produce identical ordering — without it, two slices with equal expectancy
  /// would swap places whenever the list rebuilt.
  static List<PatternMetric> ranked(
    List<PatternMetric> metrics,
    PatternSort sort,
    PatternDirection direction,
  ) {
    final int sign = direction == PatternDirection.descending ? -1 : 1;
    final List<PatternMetric> out = List<PatternMetric>.from(metrics);
    out.sort((PatternMetric a, PatternMetric b) {
      final int primary = sign * _compare(a, b, sort);
      if (primary != 0) return primary;
      // Label order is always ascending, whatever the value direction, so the tie
      // -break is itself deterministic.
      return a.label.compareTo(b.label);
    });
    return List<PatternMetric>.unmodifiable(out);
  }

  static int _compare(PatternMetric a, PatternMetric b, PatternSort sort) =>
      switch (sort) {
        PatternSort.trades => a.trades.compareTo(b.trades),
        PatternSort.netPnl => a.pnl.compareTo(b.pnl),
        PatternSort.expectancy => (a.expectancy ?? 0).compareTo(b.expectancy ?? 0),
        // Win rates are 0…1 fractions throughout; only the display multiplies by
        // 100, so comparing here needs no scaling.
        PatternSort.winRate => a.winRate.compareTo(b.winRate),
      };

  /// Net P&L descending, then label ascending.
  ///
  /// The tie-break exists purely for determinism: two slices with identical P&L
  /// must always sort the same way, or the UI would reshuffle rows between
  /// rebuilds and leak ranking would be non-reproducible.
  static int _byNetPnlThenLabel(PatternMetric a, PatternMetric b) {
    final int byPnl = b.pnl.compareTo(a.pnl);
    if (byPnl != 0) return byPnl;
    return a.label.compareTo(b.label);
  }
}

/// Running totals for one slice, weighted the way SQL weighted the average.
class _Bucket {
  _Bucket(this.value, this.label);

  final Object? value;
  final String label;

  double pnl = 0;
  int trades = 0;

  /// `win_rate * n` accumulated. SQL's `win_rate` is the mean of a 0/1 flag, so
  /// multiplying back out by its own count recovers the win count exactly, and the
  /// weighted mean over the slice is the same mean a single GROUP BY would have
  /// produced. This is recombination, not recalculation.
  double winWeighted = 0;

  void add(PatternRow row) {
    pnl += row.pnl;
    trades += row.trades;
    winWeighted += row.winRate * row.trades;
  }
}