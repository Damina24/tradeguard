import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/signal.dart';
import 'package:tradeguard/core/services/services.dart';
import 'package:tradeguard/features/signals/data/mock_signal_repository.dart';
import 'package:tradeguard/features/signals/domain/signal_stats.dart';

Signal signal({
  String id = 's1',
  SignalStatus status = SignalStatus.active,
  double? resultPips,
}) =>
    Signal(
      id: id,
      pair: 'XAUUSD',
      direction: SignalDirection.buy,
      entry: 2345.50,
      stop: 2338.00,
      tp1: 2358.00,
      confidence: 80,
      rationale: 'Test call.',
      createdAt: DateTime.utc(2026, 10, 1, 12),
      status: status,
      resultPips: resultPips,
      premium: false,
    );

/// A ledger big enough to clear the reporting floor: 12 closed calls, 8 of
/// them wins, netting +410 pips.
List<Signal> reportableLedger() => <Signal>[
      signal(id: 'a1'),
      signal(id: 'a2'),
      for (int i = 0; i < 8; i++)
        signal(id: 'w$i', status: SignalStatus.closed, resultPips: 60),
      for (int i = 0; i < 4; i++)
        signal(id: 'l$i', status: SignalStatus.closed, resultPips: -17.5),
    ];

void main() {
  group('MockSignalRepository', () {
    test('is the repository mock mode resolves', () {
      expect(Services.instance.isMock, isTrue);
      expect(Services.instance.signals, isA<MockSignalRepository>());
    });

    test('returns the seeded calls', () async {
      final List<Signal> rows = await MockSignalRepository().fetchSignals();
      expect(rows, isNotEmpty);
      expect(rows.first.pair, isNotEmpty);
    });

    test('returns an unmodifiable view', () async {
      final List<Signal> rows = await MockSignalRepository().fetchSignals();
      expect(() => rows.add(rows.first), throwsUnsupportedError);
    });

    test('respects the limit', () async {
      final List<Signal> rows =
          await MockSignalRepository().fetchSignals(limit: 1);
      expect(rows, hasLength(1));
    });
  });

  group('SignalStats', () {
    test('empty input yields the empty set, not an error', () {
      const SignalStats stats = SignalStats.empty;
      expect(stats.total, 0);
      expect(stats.closed, 0);
      expect(stats.winRate, isNull);
      expect(stats.avgPips, isNull);
    });

    test('of() on no signals is the empty set', () {
      final SignalStats stats = SignalStats.of(const <Signal>[]);
      expect(stats.total, 0);
      expect(stats.winRate, isNull);
    });

    test('open calls never count as wins, losses or pips', () {
      final SignalStats stats = SignalStats.of(<Signal>[
        signal(id: 'o1'),
        signal(id: 'o2'),
      ]);
      expect(stats.total, 2);
      expect(stats.active, 2);
      expect(stats.closed, 0);
      expect(stats.wins, 0);
      expect(stats.losses, 0);
      expect(stats.netPips, 0);
      expect(stats.winRate, isNull);
    });

    test('cancelled calls never count at all', () {
      final SignalStats stats = SignalStats.of(<Signal>[
        signal(id: 'c1', status: SignalStatus.cancelled),
      ]);
      expect(stats.total, 1);
      expect(stats.closed, 0);
      expect(stats.winRate, isNull);
    });

    test('a closed call with no recorded result is missing data, not zero', () {
      final SignalStats stats = SignalStats.of(<Signal>[
        signal(id: 'm1', status: SignalStatus.closed),
      ]);
      expect(stats.total, 1);
      expect(stats.closed, 0);
      expect(stats.netPips, 0);
    });

    test('breakeven is neither a win nor a loss', () {
      final SignalStats stats = SignalStats.of(<Signal>[
        signal(id: 'b1', status: SignalStatus.closed, resultPips: 0),
      ]);
      expect(stats.closed, 1);
      expect(stats.wins, 0);
      expect(stats.losses, 0);
    });

    test('below the floor the rate is withheld even with wins', () {
      final SignalStats stats = SignalStats.of(<Signal>[
        signal(id: 'w1', status: SignalStatus.closed, resultPips: 95),
        signal(id: 'w2', status: SignalStatus.closed, resultPips: 40),
      ]);
      expect(stats.closed, 2);
      expect(stats.hasReportableRate, isFalse);
      expect(stats.winRate, isNull);
      expect(stats.netPips, 135);
    });

    test('above the floor the rate is stated', () {
      final SignalStats stats = SignalStats.of(reportableLedger());
      expect(stats.closed, 12);
      expect(stats.hasReportableRate, isTrue);
      expect(stats.wins, 8);
      expect(stats.losses, 4);
      expect(stats.winRate, closeTo(66.67, 0.01));
      expect(stats.netPips, 410);
      expect(stats.avgPips, closeTo(34.17, 0.01));
    });
  });
}
