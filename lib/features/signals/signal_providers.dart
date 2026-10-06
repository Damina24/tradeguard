import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/signal.dart';
import '../../core/services/services.dart';
import 'data/signal_repository.dart';
import 'domain/signal_stats.dart';

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

/// Verified stats over the loaded feed, derived once from the rows.
///
/// [SignalStats.empty] is the honest fallback for the loading / empty / error
/// states: a stats card that threw or showed another feed's numbers would be
/// worse than one that shows nothing.
final Provider<SignalStats> signalStatsProvider = Provider<SignalStats>((Ref ref) {
  final SignalFeedState state = ref.watch(signalFeedProvider);
  if (state.status != SignalFeedStatus.ready || state.signals.isEmpty) {
    return SignalStats.empty;
  }
  return SignalStats.of(state.signals);
});
