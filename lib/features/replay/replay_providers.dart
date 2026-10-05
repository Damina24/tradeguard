import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/services.dart';
import 'data/price_bar_repository.dart';
import 'domain/price_bar.dart';
import 'domain/price_series.dart';
import 'domain/price_series_request.dart';
import 'domain/replay_engine.dart';
import 'domain/replay_result.dart';
import 'domain/replay_scan.dart';
import 'domain/replay_setup.dart';

/// Where the bar read currently stands.
///
/// Five states, for the same reason `PatternStatus` has them: "loading", "no cached bars for this
/// symbol", "the fetch failed", "bars are in hand" and "the series is too short to replay" are five
/// different statements, and collapsing any two of them tells the trader something false.
///
/// The engine's own `ReplayStatus` is deliberately NOT reused here: one enum meaning both "still
/// fetching" and "the stop was hit" is exactly the shortcut that makes a screen ambiguous.
enum ReplayBarsStatus { loading, empty, error, tooShort, ready }

/// The bar series for one symbol/timeframe, plus how it should be described.
class ReplayBarsState {
  const ReplayBarsState({
    this.status = ReplayBarsStatus.loading,
    this.series,
    this.failure = ReplayBarFailure.unreachable,
    this.isStubbed = false,
  });

  final ReplayBarsStatus status;

  /// The series, whenever one exists — including on the [ReplayBarsStatus.error] path, where the
  /// error describes a FAILED REFRESH of a series we are still showing. Losing the bars on a failed
  /// refresh would be the same mistake `AiReviewNotifier` avoids: discarding something the trader can
  /// still use because a network call did not land.
  final PriceSeries? series;

  /// The closed-set reason. Never a raw backend message.
  final ReplayBarFailure failure;

  /// Whether the bars are generated rather than fetched. Carried on the state, so the chart and the
  /// badge describing it cannot come from two sources that disagree.
  final bool isStubbed;

  List<PriceBar> get bars => series?.bars ?? const <PriceBar>[];

  bool get isReady => status == ReplayBarsStatus.ready;

  /// A failure that arrived while a usable series was already on screen.
  bool get isStaleFailure => status == ReplayBarsStatus.error && series != null;
}

/// Why the bar read failed. Mirrors [PriceBarFailure] one-for-one.
///
/// The duplication is deliberate and the mapping is total: [PriceBarFailure] is provider vocabulary
/// that belongs to the repository contract, while this enum is what the *screen* branches on.
/// Collapsing them would either leak provider wording into the UI or put UI decisions in `data/`.
enum ReplayBarFailure {
  /// No `TWELVEDATA_KEY` on the backend. Not fixable by the trader; the product is not deployed.
  notConfigured('Price history is not available on this build yet.'),

  /// The cache and the function could not be reached.
  unreachable('Could not load price history. Check your connection and try again.'),

  /// The fetch ran but failed.
  failed('Could not load price history for this symbol.'),

  /// Not in the catalogue.
  unknownSeries('That symbol or timeframe is not available.'),

  /// Nothing cached yet and the first fetch has not completed.
  warming('Price history for this symbol is still being fetched.');

  const ReplayBarFailure(this.message);

  /// Trader-safe wording.
  final String message;

  /// Total, one-to-one mapping onto the screen's vocabulary.
  static ReplayBarFailure from(PriceBarFailure failure) => switch (failure) {
        PriceBarFailure.notConfigured => ReplayBarFailure.notConfigured,
        PriceBarFailure.unreachable => ReplayBarFailure.unreachable,
        PriceBarFailure.failed => ReplayBarFailure.failed,
        PriceBarFailure.unknownSeries => ReplayBarFailure.unknownSeries,
        PriceBarFailure.warming => ReplayBarFailure.warming,
      };
}

/// Loads bars for one symbol/timeframe.
class ReplayBarsNotifier extends StateNotifier<ReplayBarsState> {
  ReplayBarsNotifier(this._repo, this.request) : super(const ReplayBarsState()) {
    load();
  }

  final PriceBarRepository _repo;
  final PriceSeriesRequest request;

  /// Bars below this cannot produce a usable replay.
  ///
  /// One bar can only ever fill (the engine's rule 2 forbids exiting on the entry bar) and two can
  /// only ever stop out. Letting a trader "replay" a 1-bar series would show a result the engine
  /// already knows is meaningless, so the floor is enforced here and gets its own visible state.
  static const int minimumBars = 5;

  Future<void> load() async {
    state = ReplayBarsState(
      status: ReplayBarsStatus.loading,
      series: state.series,
      isStubbed: _repo.isStubbed,
    );
    try {
      final PriceSeries series = await _repo.fetchSeries(request);
      if (!mounted) return;
      state = ReplayBarsState(
        status: _statusFor(series),
        series: series,
        isStubbed: _repo.isStubbed,
      );
    } on PriceBarException catch (e) {
      if (!mounted) return;
      // Keeps the previous series: a failed refresh must not blank a chart the trader is reading.
      state = ReplayBarsState(
        status: ReplayBarsStatus.error,
        series: state.series,
        failure: ReplayBarFailure.from(e.failure),
        isStubbed: _repo.isStubbed,
      );
    } catch (_) {
      if (!mounted) return;
      state = ReplayBarsState(
        status: ReplayBarsStatus.error,
        series: state.series,
        failure: ReplayBarFailure.unreachable,
        isStubbed: _repo.isStubbed,
      );
    }
  }

  /// Raw backend strings are never carried: a PostgREST error can name tables and columns, none of
  /// which helps a trader and some of which must not be rendered.
  static ReplayBarsStatus _statusFor(PriceSeries series) {
    if (series.isEmpty) return ReplayBarsStatus.empty;
    if (series.barCount < minimumBars) return ReplayBarsStatus.tooShort;
    return ReplayBarsStatus.ready;
  }
}

/// The symbol/timeframe pairs this build can replay.
///
/// Read from the repository rather than hardcoded in the screen, so mock and live catalogues cannot
/// drift apart — and so a test can swap in a short catalogue without touching the widget.
final Provider<List<PriceSeriesRequest>> priceCatalogueProvider =
    Provider<List<PriceSeriesRequest>>(
  (Ref ref) => Services.instance.prices.supportedSeries,
);

/// Bars for one series. Keyed by the value type, so "XAUUSD H1" resolves to a single provider.
final StateNotifierProviderFamily<ReplayBarsNotifier, ReplayBarsState,
        PriceSeriesRequest>
    replayBarsProvider =
    StateNotifierProvider.family<ReplayBarsNotifier, ReplayBarsState,
        PriceSeriesRequest>(
  (Ref ref, PriceSeriesRequest request) =>
      ReplayBarsNotifier(Services.instance.prices, request),
);

/// The series the trader is looking at. UI state, so it lives with the other providers.
final StateProvider<PriceSeriesRequest> selectedSeriesProvider =
    StateProvider<PriceSeriesRequest>(
  (Ref ref) => Services.instance.prices.supportedSeries.first,
);

/// The bars for the selected series, loaded.
final Provider<ReplayBarsState> selectedBarsProvider =
    Provider<ReplayBarsState>(
  (Ref ref) => ref.watch(replayBarsProvider(ref.watch(selectedSeriesProvider))),
);

/// Which bar the trader has stepped to, as an INDEX into the visible bars.
///
/// A provider rather than widget state, because the chart, the replay controls and the verdict card
/// must all agree on where "now" is. Three widgets each holding their own cursor is how a screen ends
/// up showing a verdict for bar 180 beside a chart drawn to bar 90.
final StateProvider<int> replayCursorProvider =
    StateProvider<int>((Ref ref) => 0);

/// The setup under test. Null until the trader picks levels, which is why
/// [replayVerdictProvider] is null rather than an empty result.
final StateProvider<ReplaySetup?> replaySetupProvider =
    StateProvider<ReplaySetup?>((Ref ref) => null);

/// The engine. Injected rather than constructed inline so a test can drive an alternative one.
final Provider<ReplayEngine> replayEngineProvider =
    Provider<ReplayEngine>((Ref ref) => const ReplayEngine());

/// Reporting floor for the scan. Injectable so a test can drive the exact boundary.
final Provider<ReplayScanThresholds> replayScanThresholdsProvider =
    Provider<ReplayScanThresholds>(
  (Ref ref) => const ReplayScanThresholds(),
);

/// How many bars the chart shows and the replay walks.
///
/// Always a PREFIX of the series: the cursor moves forward from the end of what was known, so a bar
/// can never influence a verdict computed before it was stepped to. Slicing here rather than inside
/// the widget is what makes that guarantee structural instead of a thing to remember.
final Provider<List<PriceBar>> visibleBarsProvider =
    Provider<List<PriceBar>>((Ref ref) {
  final ReplayBarsState state = ref.watch(selectedBarsProvider);
  final int cursor = ref.watch(replayCursorProvider);
  final List<PriceBar> bars = state.bars;
  if (bars.isEmpty) return const <PriceBar>[];
  final int end = cursor < 0
      ? 0
      : (cursor >= bars.length ? bars.length : cursor + 1);
  return bars.sublist(0, end);
});

/// The single-setup verdict over [visibleBarsProvider]. Null until a valid setup exists.
final Provider<ReplayResult?> replayVerdictProvider =
    Provider<ReplayResult?>((Ref ref) {
  final ReplaySetup? setup = ref.watch(replaySetupProvider);
  if (setup == null || !setup.isValid) return null;
  return ref.watch(replayEngineProvider).run(ref.watch(visibleBarsProvider), setup);
});

/// The whole-series scan for the current setup's SHAPE, independent of the cursor.
///
/// Deliberately NOT restricted to [visibleBarsProvider]: a scan is a statement about the series, and
/// recomputing it as the trader steps would make the same screen show two different win rates. It is
/// labelled as covering the full history either way.
final Provider<ReplayScan> replayScanProvider = Provider<ReplayScan>(
  (Ref ref) {
  final ReplaySetup? setup = ref.watch(replaySetupProvider);
  final List<PriceBar> bars = ref.watch(selectedBarsProvider).bars;
  if (setup == null || !setup.isValid || bars.isEmpty) {
    return ReplayScan.empty(
      minimumTrades: ref.watch(replayScanThresholdsProvider).minTrades,
    );
  }
  return ReplayScan.run(
    bars: bars,
    setup: setup,
    engine: ref.watch(replayEngineProvider),
    thresholds: ref.watch(replayScanThresholdsProvider),
  );
});

/// The bar the cursor is on, or null when there is nothing to point at.
final Provider<PriceBar?> replayCursorBarProvider =
    Provider<PriceBar?>((Ref ref) {
  final List<PriceBar> bars = ref.watch(visibleBarsProvider);
  return bars.isEmpty ? null : bars.last;
});