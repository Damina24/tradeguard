import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/signal.dart';
import '../../core/services/services.dart';
import '../replay/domain/price_series.dart';
import '../replay/domain/price_series_request.dart';
import '../replay/replay_providers.dart';
import 'data/signal_repository.dart';
import 'domain/signal_stats.dart';
import 'domain/volatility_score.dart';

/// Where the signal feed read currently stands.
///
/// Four states, not two, because they call for different words and different
/// next actions from the trader:
///   * [loading] — still asking the repository.
///   * [empty]   — the table returned nothing: no signals posted yet.
///   * [error]   — the read failed. Never rendered as "no signals".
///   * [ready]   — rows are in hand; the *ledger* may still be too thin to
///     state a win rate (see [SignalStats.hasReportableRate]), which is a
///     different message.
///
/// The distinction that matters: "not enough closed calls to state a rate"
/// must not look like "the desk loses". A new desk shown the second would be
/// judged on a sample that cannot support any judgement.
enum SignalFeedStatus { loading, empty, error, ready }

/// Raw result of the repository read.
///
/// Kept as persisted facts only — no derived numbers — so this state can
/// never be read as a second opinion about performance.
class SignalFeedState {
  const SignalFeedState({
    this.status = SignalFeedStatus.loading,
    this.signals = const <Signal>[],
    this.isStubbed = false,
  });

  /// The error state. Carries no exception, on purpose: a PostgREST error
  /// names tables and columns, and nothing it says is worth showing a trader.
  factory SignalFeedState.error({required bool isStubbed}) =>
      SignalFeedState(status: SignalFeedStatus.error, isStubbed: isStubbed);

  final SignalFeedStatus status;

  /// Signals as the repository returned them, newest first.
  final List<Signal> signals;

  /// Whether the feed is the offline seed. Carried on the state, so the feed
  /// and the badge describing it cannot come from two sources that disagree.
  final bool isStubbed;

  bool get isReady => status == SignalFeedStatus.ready;
}

/// Loads the `signals` feed.
///
/// Account isolation comes from the repository, not from here: this notifier
/// has no user parameter and no way to be asked for another trader's data.
/// The table holds operator-posted rows readable by any signed-in trader, and
/// the repository reads identity from the session.
class SignalFeedNotifier extends StateNotifier<SignalFeedState> {
  SignalFeedNotifier(this._repo) : super(SignalFeedState(isStubbed: _repo.isStubbed)) {
    unawaited(refresh());
  }

  final SignalRepository _repo;

  Future<void> refresh() async {
    try {
      final List<Signal> rows = await _repo.fetchSignals();
      if (!mounted) return;
      state = SignalFeedState(
        status: rows.isEmpty ? SignalFeedStatus.empty : SignalFeedStatus.ready,
        signals: List<Signal>.unmodifiable(rows),
        isStubbed: _repo.isStubbed,
      );
    } catch (_) {
      if (!mounted) return;
      state = SignalFeedState.error(isStubbed: _repo.isStubbed);
    }
  }
}

final StateNotifierProvider<SignalFeedNotifier, SignalFeedState>
    signalFeedProvider =
    StateNotifierProvider<SignalFeedNotifier, SignalFeedState>(
  (Ref ref) => SignalFeedNotifier(Services.instance.signals),
);

/// Verified stats over the loaded feed, derived once from the rows, with the
/// volatility radar attached when market bars are in hand.
///
/// [SignalStats.empty] is the honest fallback for the loading / empty / error
/// states: a stats card that threw or showed another feed's numbers would be
/// worse than one that shows nothing. The radar is watched separately and
/// attached via `withVolatility`, so a feed that has not loaded can still
/// show a measured radar (and vice versa) — they are two observations on one
/// card, not one derived from the other.
final Provider<SignalStats> signalStatsProvider = Provider<SignalStats>((Ref ref) {
  final SignalFeedState state = ref.watch(signalFeedProvider);
  final SignalStats base = (state.status != SignalFeedStatus.ready ||
          state.signals.isEmpty)
      ? SignalStats.empty
      : SignalStats.of(state.signals);
  return base.withVolatility(ref.watch(signalVolatilityProvider));
});

/// The series the volatility radar measures.
///
/// The FIRST series in the repository's own catalogue — the same rule the
/// replay screen's `selectedSeriesProvider` uses — rather than a hardcoded
/// symbol: a fixed string would silently point outside a shortened catalogue
/// (a test or a deployment that serves fewer series) and fetch nothing, while
/// this stays valid by construction. Read from the repository rather than
/// duplicated here, so mock and live catalogues cannot drift apart.
///
/// The radar deliberately does NOT follow `selectedSeriesProvider`: a trader
/// stepping through a replay must not watch the signals radar change
/// underneath them. One stable series, labelled on screen with its symbol,
/// timeframe and provenance.
final Provider<PriceSeriesRequest> signalRadarSeriesProvider =
    Provider<PriceSeriesRequest>(
  (Ref ref) => Services.instance.prices.supportedSeries.first,
);

/// The bars behind the radar.
///
/// Reuses the replay feature's `replayBarsProvider` family rather than
/// loading a second copy of the same `prices_cache` row: the two screens ask
/// the identical question of the identical repository, and Riverpod's family
/// cache means one fetch serves both. The replay feature owns the bar read
/// (its repository, its five-state vocabulary) — the signals feature only
/// consumes it, which is why this seam is a provider rather than a second
/// notifier that would have to re-learn `loading` vs `warming` vs
/// `tooShort`.
///
/// `ReplayBarsStatus` is the right vocabulary here too: "still fetching",
/// "the read failed" and "there are no bars for this series" are three
/// different things for the radar to print, exactly as for the chart.
final Provider<ReplayBarsState> signalRadarBarsProvider =
    Provider<ReplayBarsState>(
  (Ref ref) => ref.watch(replayBarsProvider(ref.watch(signalRadarSeriesProvider))),
);

/// The volatility score, or null while no usable series exists.
///
/// Null in every state where a score would be a guess: bars still loading,
/// the read failed with nothing cached, a series too short to clear
/// [VolatilityScore.minBars]. The card renders each of those as its own
/// message — never as 0, which would read as "market dead calm".
///
/// A FAILED REFRESH that still carries the previous series (the state replay
/// calls `isStaleFailure`) still scores: losing a working reading because a
/// network call did not land is the same mistake `ReplayBarsNotifier`
/// refuses to make on the chart.
final Provider<VolatilityScore?> signalVolatilityProvider =
    Provider<VolatilityScore?>((Ref ref) {
  final ReplayBarsState bars = ref.watch(signalRadarBarsProvider);
  final PriceSeries? series = bars.series;
  if (series == null) return null;
  return VolatilityScore.of(series.bars);
});
