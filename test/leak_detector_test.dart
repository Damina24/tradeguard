import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/features/patterns/domain/leak_detector.dart';
import 'package:tradeguard/features/patterns/domain/leak_thresholds.dart';
import 'package:tradeguard/features/patterns/domain/pattern_dimension.dart';
import 'package:tradeguard/features/patterns/domain/pattern_metrics.dart';
import 'package:tradeguard/features/patterns/domain/pattern_row.dart';
import 'package:tradeguard/features/patterns/domain/trading_leak.dart';

/// A `v_patterns` row. Defaults describe a healthy slice.
PatternRow row({
  String userId = 'u1',
  String? symbol = 'EURUSD',
  String? session = 'london',
  int? dayOfWeek = 1,
  int? hour = 8,
  double pnl = 500,
  int trades = 20,
  double winRate = 0.6,
}) =>
    PatternRow(
      userId: userId,
      symbol: symbol,
      session: session,
      dayOfWeek: dayOfWeek,
      hour: hour,
      pnl: pnl,
      trades: trades,
      winRate: winRate,
    );

const LeakDetector detector = LeakDetector();

void main() {
  group('no leaks', () {
    test('an empty journal reports nothing and no data', () {
      final LeakReport report = detector.detectRows(const <PatternRow>[]);
      expect(report.leaks, isEmpty);
      expect(report.sampleTrades, 0);
      expect(report.isInsufficient, isFalse);
    });

    test('an entirely profitable journal reports nothing', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'A', pnl: 900),
        row(symbol: 'B', pnl: 120),
      ]);
      expect(report.leaks, isEmpty);
      expect(report.sampleTrades, 40);
    });

    test('break-even slices are not leaks', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'A', pnl: 0),
      ]);
      expect(report.leaks, isEmpty);
    });

    test('still reports how much it reviewed when nothing qualified', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'A', pnl: 900),
        row(symbol: 'B', pnl: 120),
      ]);
      expect(report.reviewedSlices, greaterThan(0));
    });
  });

  group('insufficient sample', () {
    test('a single losing trade never becomes a leak', () {
      // The spec never asks for single-trade warnings, and one -$9000 outlier is
      // the single most likely false positive this feature could ship.
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'XAUUSD', pnl: -9000, trades: 1, winRate: 0),
      ]);
      expect(report.leaks, isEmpty);
    });

    test('a slice one trade below the floor is still withheld', () {
      const LeakDetector strict = LeakDetector(
        thresholds: LeakThresholds(minTrades: 6),
      );
      final LeakReport report = strict.detectRows(<PatternRow>[
        row(pnl: -800, trades: 5),
      ]);
      expect(report.leaks, isEmpty);
    });

    test('exactly at the floor is reported', () {
      const LeakDetector strict = LeakDetector(
        thresholds: LeakThresholds(minTrades: 6),
      );
      final LeakReport report = strict.detectRows(<PatternRow>[
        row(pnl: -800, trades: 6),
      ]);
      expect(report.leaks, isNotEmpty);
    });

    test('the report states the sample size and the gate', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(trades: 30),
      ]);
      expect(report.sampleTrades, 30);
      expect(report.minimumTrades, 5);
    });
  });

  group('netNegativeSlice', () {
    test('a net-negative slice with enough trades is a leak', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'XAUUSD', session: 'london', pnl: -1420.50, trades: 24),
      ]);
      final TradingLeak leak = report.leaks.first;
      expect(leak.kind, LeakKind.netNegativeSlice);
      expect(leak.label, 'XAUUSD');
      expect(leak.pnl, -1420.50);
      expect(leak.trades, 24);
    });

    test('the title names the slice in plain words', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'XAUUSD', pnl: -800, trades: 12),
      ]);
      expect(report.leaks.first.title, 'XAUUSD trades is net negative');
    });

    test('a session leak reads as a session', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'A', session: 'london', pnl: -300, trades: 12),
        row(symbol: 'B', session: 'newyork', pnl: 900, trades: 12),
      ]);
      final TradingLeak leak = report.leaks.firstWhere(
        (TradingLeak x) => x.dimension == PatternDimension.session,
      );
      expect(leak.title, contains('London'));
    });

    test('an hour leak names the hour', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(hour: 3, pnl: -400, trades: 12),
        row(hour: 14, pnl: 900, trades: 12),
      ]);
      final TradingLeak leak = report.leaks.firstWhere(
        (TradingLeak x) => x.dimension == PatternDimension.hour,
      );
      expect(leak.title, contains('03:00'));
    });

    test('a weekday leak names the day', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(dayOfWeek: 5, pnl: -400, trades: 12),
        row(dayOfWeek: 1, pnl: 900, trades: 12),
      ]);
      final TradingLeak leak = report.leaks.firstWhere(
        (TradingLeak x) => x.dimension == PatternDimension.dayOfWeek,
      );
      expect(leak.title, contains('Friday'));
    });

    test('the same weakness surfaces once per dimension it appears in', () {
      // A trader losing on XAUUSD in London has one problem, but the view exposes
      // it on two axes. Reporting both is the honest reading: dropping one would
      // understate where the loss is concentrated.
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'XAUUSD', session: 'london', pnl: -800, trades: 12),
        row(symbol: 'EURUSD', session: 'newyork', pnl: 900, trades: 12),
      ]);
      expect(
        report.leaks
            .where((TradingLeak x) => x.dimension == PatternDimension.symbol),
        isNotEmpty,
      );
      expect(
        report.leaks
            .where((TradingLeak x) => x.dimension == PatternDimension.session),
        isNotEmpty,
      );
    });
  });

  group('lossConcentration', () {
    test('a slice holding most of the losses is flagged as concentrated', () {
      // Distinct sessions so the rows stay separate on every dimension: sharing
      // one session would make that session 100% of the losses, which is a
      // different (and valid) finding.
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'BAD', session: 'london', hour: 8, pnl: -900, trades: 20),
        row(symbol: 'SMALL1', session: 'newyork', hour: 14, pnl: -60, trades: 8),
        row(symbol: 'SMALL2', session: 'asia', hour: 3, pnl: -40, trades: 8),
      ]);
      expect(
        report.leaks.map((TradingLeak x) => x.kind),
        contains(LeakKind.lossConcentration),
      );
      final TradingLeak concentrated = report.leaks.firstWhere(
        (TradingLeak x) =>
            x.kind == LeakKind.lossConcentration &&
            x.dimension == PatternDimension.symbol,
      );
      expect(concentrated.label, 'BAD');
    });

    test('a slice below the loss share is not called concentrated', () {
      // Three equal losers: each holds a third of the losses, so none reaches
      // the 40% plurality the rule asks for.
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'A', session: 'london', pnl: -300, trades: 20),
        row(symbol: 'B', session: 'newyork', pnl: -300, trades: 20),
        row(symbol: 'C', session: 'asia', pnl: -300, trades: 20),
      ]);
      expect(
        report.leaks.where(
          (TradingLeak x) =>
              x.kind == LeakKind.lossConcentration &&
              x.dimension == PatternDimension.symbol,
        ),
        isEmpty,
      );
    });

    test('the evidence quotes the share of total losses', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'BAD', session: 'london', pnl: -900, trades: 20),
        row(symbol: 'OK', session: 'newyork', pnl: -100, trades: 8),
      ]);
      final TradingLeak leak = report.leaks.firstWhere(
        (TradingLeak x) =>
            x.kind == LeakKind.lossConcentration &&
            x.dimension == PatternDimension.symbol,
      );
      expect(
        leak.evidence.any((String e) => e.contains('90%')),
        isTrue,
        reason: leak.evidence.join(' | '),
      );
    });

    test('no concentration is claimed when the journal has no losses', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'A', pnl: 900, trades: 20),
      ]);
      expect(report.leaks, isEmpty);
    });
  });

  group('multiple leaks', () {
    List<PatternRow> several() => <PatternRow>[
          row(symbol: 'WORST', pnl: -2000, trades: 30),
          row(symbol: 'MIDDLE', pnl: -600, trades: 15),
          row(symbol: 'GOOD', pnl: 2500, trades: 25),
        ];

    test('every qualifying slice is reported', () {
      final LeakReport report = detector.detectRows(several());
      expect(
        report.leaks
            .map((TradingLeak x) => x.label)
            .toSet()
            .containsAll(<String>{'WORST', 'MIDDLE'}),
        isTrue,
      );
    });

    test('orders worst net result first', () {
      final LeakReport report = detector.detectRows(several());
      final List<double> pnl =
          report.leaks.map((TradingLeak x) => x.pnl).toList();
      final List<double> sorted = List<double>.from(pnl)..sort();
      expect(pnl, sorted);
      expect(report.leaks.first.label, 'WORST');
    });

    test('is deterministic  the same rows give the same order every time', () {
      final List<String> a = detector
          .detectRows(several())
          .leaks
          .map((TradingLeak x) => '${x.kind}:${x.label}')
          .toList();
      final List<String> b = detector
          .detectRows(several())
          .leaks
          .map((TradingLeak x) => '${x.kind}:${x.label}')
          .toList();
      expect(a, b);
    });

    test('a profitable slice never appears', () {
      final LeakReport report = detector.detectRows(several());
      expect(report.leaks.map((TradingLeak x) => x.label), isNot(contains('GOOD')));
    });
  });

  group('confidence', () {
    test('scales with the sample behind the finding', () {
      LeakConfidence at(int trades) => detector
          .detectRows(<PatternRow>[row(pnl: -100, trades: trades)])
          .leaks
          .first
          .confidence;

      expect(at(5), LeakConfidence.low);
      expect(at(19), LeakConfidence.low);
      expect(at(20), LeakConfidence.moderate);
      expect(at(49), LeakConfidence.moderate);
      expect(at(50), LeakConfidence.high);
      expect(at(500), LeakConfidence.high);
    });

    test('a slice below the floor can never reach a confidence label', () {
      expect(
        LeakConfidence.fromTrades(3, const LeakThresholds()),
        LeakConfidence.tooSmall,
      );
    });

    test('every confidence has wording and a caveat', () {
      for (final LeakConfidence c in LeakConfidence.values) {
        expect(c.label, isNotEmpty);
        expect(c.caveat, isNotEmpty);
      }
    });

    test('the thin-sample caveat is not a recommendation to act', () {
      expect(LeakConfidence.tooSmall.caveat, contains('Not enough trades'));
    });
  });

  group('evidence and recommendations', () {
    TradingLeak sampleLeak() => detector
        .detectRows(<PatternRow>[row(symbol: 'XAUUSD', pnl: -1200, trades: 24)])
        .leaks
        .first;

    test('evidence states the trade count, net result and hit rate', () {
      final String evidence = sampleLeak().evidence.first;
      expect(evidence, contains('24 trades'));
      expect(evidence, contains('-\$1,200'));
      expect(evidence, contains('14 of 24 won'));
    });

    test('evidence includes the average per trade', () {
      expect(
        sampleLeak().evidence.any((String e) => e.contains('Average per trade')),
        isTrue,
      );
    });

    test('the sample size is on the leak itself, not just in the evidence', () {
      expect(sampleLeak().trades, 24);
    });

    test('the recommendation never promises a result or issues an instruction',
        () {
      for (final TradingLeak leak in detector.detectRows(<PatternRow>[
        row(symbol: 'A', pnl: -900, trades: 25),
        row(symbol: 'B', pnl: -800, trades: 8),
      ]).leaks) {
        final String r = leak.recommendation.toLowerCase();
        expect(r, isNot(contains('guarantee')));
        expect(r, isNot(contains('will fix')));
        expect(r, isNot(contains('you must')));
        expect(r, isNot(contains('stop trading')));
      }
    });

    test('a large sample says plainly that cause is unknown', () {
      final TradingLeak big = detector
          .detectRows(<PatternRow>[row(pnl: -4000, trades: 60)])
          .leaks
          .first;
      expect(big.confidence, LeakConfidence.high);
      expect(big.recommendation, contains('cannot tell you why'));
    });

    test('a small sample is hedged', () {
      final TradingLeak small = detector
          .detectRows(<PatternRow>[row(pnl: -400, trades: 6)])
          .leaks
          .first;
      expect(small.confidence, LeakConfidence.low);
      expect(small.recommendation, contains('small number of trades'));
    });

    test('LeakEvidence formats a one-trade slice without pluralising wrongly', () {
      expect(
        LeakEvidence.summary(trades: 1, pnl: -10, winRate: 0),
        contains('1 trade '),
      );
    });

    test(
        'LeakEvidence reports unavailable expectancy rather than dividing by zero',
        () {
      expect(LeakEvidence.expectancy(null), 'Average per trade: not available');
    });
  });

  group('thresholds are honoured', () {
    test('a custom loss share changes which slice is concentrated', () {
      const LeakDetector strict =
          LeakDetector(thresholds: LeakThresholds(lossShare: 0.90));
      final List<PatternRow> rows = <PatternRow>[
        row(symbol: 'A', session: 'london', pnl: -700, trades: 20),
        row(symbol: 'B', session: 'newyork', pnl: -300, trades: 20),
      ];
      // 70% < 90%, so nothing is called concentrated at this setting.
      expect(
        strict.detectRows(rows).leaks.where(
          (TradingLeak x) =>
              x.kind == LeakKind.lossConcentration &&
              x.dimension == PatternDimension.symbol,
        ),
        isEmpty,
      );
      // The default 40% would have flagged A.
      expect(
        detector.detectRows(rows).leaks.where(
          (TradingLeak x) =>
              x.kind == LeakKind.lossConcentration &&
              x.dimension == PatternDimension.symbol,
        ),
        isNotEmpty,
      );
    });

    test('defaults are the documented conservative values', () {
      const LeakThresholds t = LeakThresholds();
      expect(t.minTrades, 5);
      expect(t.moderateTrades, 20);
      expect(t.highTrades, 50);
      expect(t.lossShare, 0.40);
    });

    test('the confidence tiers are monotonic', () {
      const LeakThresholds t = LeakThresholds();
      expect(t.minTrades, lessThan(t.moderateTrades));
      expect(t.moderateTrades, lessThan(t.highTrades));
    });
  });

  group('hostile and edge inputs', () {
    test('handles an enormous loss without overflowing anything', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'BIG', pnl: -1e12, trades: 100),
      ]);
      expect(report.leaks.first.pnl, -1e12);
    });

    test('handles a very large trade count', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'MANY', pnl: -50, trades: 500000),
      ]);
      expect(report.leaks.first.trades, 500000);
      expect(report.leaks.first.confidence, LeakConfidence.high);
    });

    test('handles a very long symbol in the title', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'Y' * 200, pnl: -900, trades: 20),
      ]);
      expect(report.leaks.first.label.length, 200);
    });

    test('an untagged losing slice is reported under a readable name', () {
      final LeakReport report = detector.detectRows(<PatternRow>[
        row(symbol: 'A', session: null, pnl: -900, trades: 20),
      ]);
      expect(
        report.leaks
            .where((TradingLeak x) => x.dimension == PatternDimension.session)
            .map((TradingLeak x) => x.label),
        contains('Untagged'),
      );
    });

    test('a zero-trade slice has no expectancy rather than a division error', () {
      // SQL cannot emit this, but a hand-built row must not crash the detector.
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[row(trades: 0)],
        PatternDimension.symbol,
      );
      expect(m.metrics.single.expectancy, isNull);
      expect(detector.detect(<PatternMetrics>[m]).leaks, isEmpty);
    });

    test('metrics with no slices at all yield an empty report', () {
      final LeakReport report = detector.detect(<PatternMetrics>[
        PatternMetrics.empty(PatternDimension.symbol),
      ]);
      expect(report.leaks, isEmpty);
      expect(report.sampleTrades, 0);
    });
  });
}
