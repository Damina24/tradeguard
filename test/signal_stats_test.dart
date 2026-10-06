import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/signal.dart';
import 'package:tradeguard/core/services/services.dart';
import 'package:tradeguard/features/signals/data/mock_signal_repository.dart';
import 'package:tradeguard/features/signals/domain/signal_stats.dart';
import 'package:tradeguard/features/signals/domain/volatility_score.dart';

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

  group('SignalStats volatility wiring', () {
    const VolatilityScore score = VolatilityScore(
      score: 64,
      barCount: 240,
      baselineAtr: 1.2,
      recentAtr: 1.8,
      rangePct: 0.31,
      expansionPct: 50,
    );

    test('of() never reads prices — volatility starts null', () {
      final SignalStats stats = SignalStats.of(reportableLedger());
      expect(stats.volatility, isNull);
      expect(SignalStats.empty.volatility, isNull);
    });

    test('withVolatility attaches the score and leaves the ledger untouched',
        () {
      final SignalStats base = SignalStats.of(reportableLedger());
      final SignalStats withScore = base.withVolatility(score);

      expect(withScore.volatility, same(score));
      expect(withScore.total, base.total);
      expect(withScore.closed, base.closed);
      expect(withScore.wins, base.wins);
      expect(withScore.losses, base.losses);
      expect(withScore.netPips, base.netPips);
      expect(withScore.avgPips, base.avgPips);
      expect(withScore.winRate, base.winRate);
    });

    test('the original stats are unchanged — stats stay immutable', () {
      final SignalStats base = SignalStats.of(reportableLedger());
      base.withVolatility(score);
      expect(base.volatility, isNull);
    });

    test('empty ledger stats can still carry a radar reading', () {
      final SignalStats stats = SignalStats.empty.withVolatility(score);
      expect(stats.total, 0);
      expect(stats.winRate, isNull);
      expect(stats.volatility, same(score));
    });

    test('withVolatility(null) clears the reading', () {
      final SignalStats stats =
          SignalStats.empty.withVolatility(score).withVolatility(null);
      expect(stats.volatility, isNull);
    });

    test('toString reports the score, or null when not measured', () {
      expect(
        SignalStats.empty.withVolatility(score).toString(),
        contains('volatility=64'),
      );
      expect(SignalStats.empty.toString(), contains('volatility=null'));
    });
  });
}
