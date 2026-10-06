import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/signal.dart';
import 'package:tradeguard/features/signals/data/mock_signal_repository.dart';
import 'package:tradeguard/features/signals/data/signal_repository.dart';
import 'package:tradeguard/features/signals/signal_providers.dart';

/// A repository that answers with whatever it was handed, so the feed can be
/// driven through each state without a backend.
class FakeSignalRepository implements SignalRepository {
  FakeSignalRepository({this.signals, this.failure, this.stubbed = false});

  final List<Signal>? signals;
  final Object? failure;
  final bool stubbed;

  @override
  bool get isStubbed => stubbed;

  @override
  Future<List<Signal>> fetchSignals({int limit = 100}) async {
    final Object? f = failure;
    if (f != null) throw f;
    return List<Signal>.unmodifiable(
      (signals ?? const <Signal>[]).take(limit),
    );
  }
}

Signal signal({String id = 's1'}) => Signal(
      id: id,
      pair: 'XAUUSD',
      direction: SignalDirection.buy,
      entry: 2345.50,
      stop: 2338.00,
      tp1: 2358.00,
      confidence: 80,
      rationale: 'Test call.',
      createdAt: DateTime.utc(2026, 10, 1, 12),
      premium: false,
    );

void main() {
  group('SignalFeedNotifier', () {
    test('starts in the loading state, not the empty state', () async {
      final SignalFeedNotifier notifier = SignalFeedNotifier(
        FakeSignalRepository(signals: const <Signal>[]),
      );
      expect(notifier.state.status, SignalFeedStatus.loading);
      await notifier.refresh();
      expect(notifier.state.status, SignalFeedStatus.empty);
    });

    test('an empty result is the empty state, not an error', () async {
      final SignalFeedNotifier notifier = SignalFeedNotifier(
        FakeSignalRepository(signals: const <Signal>[]),
      );
      await notifier.refresh();
      expect(notifier.state.status, SignalFeedStatus.empty);
      expect(notifier.state.isReady, isFalse);
    });

    test('rows produce the ready state', () async {
      final SignalFeedNotifier notifier = SignalFeedNotifier(
        FakeSignalRepository(signals: <Signal>[signal()]),
      );
      await notifier.refresh();
      expect(notifier.state.status, SignalFeedStatus.ready);
      expect(notifier.state.signals, hasLength(1));
    });

    test('a failure becomes the error state, not the empty state', () async {
      final SignalFeedNotifier notifier = SignalFeedNotifier(
        FakeSignalRepository(failure: StateError('boom')),
      );
      await notifier.refresh();
      expect(notifier.state.status, SignalFeedStatus.error);
    });

    test('the error state carries no raw exception', () async {
      final SignalFeedNotifier notifier = SignalFeedNotifier(
        FakeSignalRepository(
          failure:
              const SignalDataException('relation "signals" does not exist'),
        ),
      );
      await notifier.refresh();
      expect(notifier.state.toString(), isNot(contains('relation')));
    });

    test('the row list handed to the UI is unmodifiable', () async {
      final SignalFeedNotifier notifier = SignalFeedNotifier(
        MockSignalRepository(),
      );
      await notifier.refresh();
      expect(
        () => notifier.state.signals.add(notifier.state.signals.first),
        throwsUnsupportedError,
      );
    });

    test('stubbed state follows the repository', () async {
      final SignalFeedNotifier live =
          SignalFeedNotifier(FakeSignalRepository(stubbed: false));
      await live.refresh();
      expect(live.state.isStubbed, isFalse);
      final SignalFeedNotifier demo =
          SignalFeedNotifier(FakeSignalRepository(stubbed: true));
      await demo.refresh();
      expect(demo.state.isStubbed, isTrue);
    });
  });
}
