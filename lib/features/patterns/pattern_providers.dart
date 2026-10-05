import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/providers.dart';
import '../../core/services/services.dart';
import 'data/pattern_repository.dart';
import 'domain/leak_detector.dart';
import 'domain/leak_thresholds.dart';
import 'domain/pattern_dimension.dart';
import 'domain/pattern_metrics.dart';
import 'domain/pattern_row.dart';
import 'domain/trading_leak.dart';

/// Where the pattern read currently stands.
///
/// Five states, not three, because they call for different words and different
/// next actions from the trader:
///   * [loading] — still asking the repository.
///   * [empty]   — the view returned nothing: this journal has no trades yet.
///   * [error]   — the read failed. Never rendered as "no patterns".
///   * [ready]   — rows are in hand; the *slice* may still be too thin to read
///     (see [PatternInsights.insufficientData]), which is a different message.
///
/// The distinction that matters: "not enough data to identify a pattern" must not
/// look like "you have no patterns". A new trader shown the second would conclude
/// something is wrong with their trading rather than that they need more closed
/// trades.
enum PatternStatus { loading, empty, error, ready }

/// Raw result of the repository read.
///
/// Kept as persisted-aggregate facts only — no derived numbers — so this state can
/// never be read as a second opinion about performance.
class PatternState {
  const PatternState({
    this.status = PatternStatus.loading,
    this.rows = const <PatternRow>[],
  });

  /// The error state. Carries no exception, on purpose: a PostgREST error names
  /// tables and columns, and nothing it says is worth showing a trader.
  factory PatternState.error() => const PatternState(status: PatternStatus.error);

  final PatternStatus status;

  /// Rows as `v_patterns` returned them.
  final List<PatternRow> rows;

  bool get isReady => status == PatternStatus.ready;

  /// Total trades behind the rows — the honest sample size for every claim.
  int get totalTrades =>
      rows.fold<int>(0, (int s, PatternRow r) => s + r.trades);
}

/// Loads `v_patterns` for the signed-in trader.
///
/// Account isolation comes from the repository, not from here: this notifier has
/// no user parameter and no way to be asked for another account's data.
class PatternNotifier extends StateNotifier<PatternState> {
  PatternNotifier(this._repo) : super(const PatternState()) {
    unawaited(refresh());
  }

  final PatternRepository _repo;

  Future<void> refresh() async {
    try {
      final List<PatternRow> rows = await _repo.fetchPatterns();
      if (!mounted) return;
      state = PatternState(
        status: rows.isEmpty ? PatternStatus.empty : PatternStatus.ready,
        rows: List<PatternRow>.unmodifiable(rows),
      );
    } catch (_) {
      if (!mounted) return;
      state = PatternState.error();
    }
  }
}

final StateNotifierProvider<PatternNotifier, PatternState> patternStateProvider =
    StateNotifierProvider<PatternNotifier, PatternState>(
  (Ref ref) => PatternNotifier(Services.instance.patterns),
);

/// Leak thresholds, injectable so tests can drive the exact boundary.
final Provider<LeakThresholds> leakThresholdsProvider =
    Provider<LeakThresholds>((Ref ref) => const LeakThresholds());

final Provider<LeakDetector> leakDetectorProvider =
    Provider<LeakDetector>(
  (Ref ref) => LeakDetector(thresholds: ref.watch(leakThresholdsProvider)),
);

/// Everything the screen needs, derived once from the rows.
///
/// [insufficientData] is the honest middle state: trades exist, but fewer than the
/// detector would ever report on. It is a first-class flag rather than something
/// the UI infers for itself, so the two tabs cannot disagree about it.
class PatternInsights {
  const PatternInsights({
    required this.metricsByDimension,
    required this.report,
    required this.insufficientData,
    required this.sampleTrades,
  });

  /// The empty set, used by the loading / empty / error states.
  static final PatternInsights none = PatternInsights(
    metricsByDimension: const <PatternDimension, PatternMetrics>{},
    report: LeakReport.empty(),
    insufficientData: false,
    sampleTrades: 0,
  );

  /// Every dimension the view supports, keyed by it.
  final Map<PatternDimension, PatternMetrics> metricsByDimension;

  /// The leak sweep across every dimension.
  final LeakReport report;

  /// Trades exist but sit below the reporting floor.
  final bool insufficientData;

  /// Total trades across the journal.
  final int sampleTrades;

  List<TradingLeak> get leaks => report.leaks;
}

final Provider<PatternInsights> patternInsightsProvider =
    Provider<PatternInsights>((Ref ref) {
  final PatternState state = ref.watch(patternStateProvider);
  if (state.status != PatternStatus.ready || state.rows.isEmpty) {
    return PatternInsights.none;
  }

  final LeakThresholds thresholds = ref.watch(leakThresholdsProvider);
  final List<PatternMetrics> all = PatternMetrics.allDimensions(state.rows);

  return PatternInsights(
    metricsByDimension: <PatternDimension, PatternMetrics>{
      for (final PatternMetrics m in all) m.dimension: m,
    },
    report: ref.watch(leakDetectorProvider).detect(all),
    insufficientData: state.totalTrades < thresholds.minTrades,
    sampleTrades: state.totalTrades,
  );
});

/// Metrics for one dimension. A dimension with no data yields the empty set rather
/// than null, so the screen has a single code path.
final ProviderFamily<PatternMetrics, PatternDimension> patternMetricsProvider =
    Provider.family<PatternMetrics, PatternDimension>((Ref ref, dimension) {
  return ref.watch(patternInsightsProvider).metricsByDimension[dimension] ??
      PatternMetrics.empty(dimension);
});

/// Which dimension the pattern views are showing. UI state, so it lives with the
/// other providers rather than inside a widget's `State`.
final StateProvider<PatternDimension> selectedPatternDimensionProvider =
    StateProvider<PatternDimension>(
  (Ref ref) => PatternDimension.symbol,
);

/// How the pattern list is ordered.
final StateProvider<PatternSort> patternSortProvider =
    StateProvider<PatternSort>((Ref ref) => PatternSort.expectancy);

final StateProvider<PatternDirection> patternDirectionProvider =
    StateProvider<PatternDirection>(
  (Ref ref) => PatternDirection.ascending,
);

/// Trades in the trader's own trade list.
///
/// Read so the screen can state how many trades the pattern read covers beside the
/// journal's own count. A gap there means `v_patterns` and the `trades` table have
/// drifted, which is worth saying rather than hiding.
final Provider<int> journalTradeCountProvider = Provider<int>(
  (Ref ref) => ref.watch(tradesProvider).length,
);