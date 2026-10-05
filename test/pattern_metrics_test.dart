import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/features/patterns/domain/pattern_dimension.dart';
import 'package:tradeguard/features/patterns/domain/pattern_metrics.dart';
import 'package:tradeguard/features/patterns/domain/pattern_row.dart';

/// A `v_patterns` row, built the way the view returns one.
PatternRow row({
  String userId = 'u1',
  String? symbol = 'EURUSD',
  String? session = 'london',
  int? dayOfWeek = 1,
  int? hour = 8,
  double pnl = 100,
  int trades = 10,
  double winRate = 0.5,
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

void main() {
  group('PatternRow.fromJson', () {
    test('parses the exact columns v_patterns projects', () {
      final PatternRow r = PatternRow.fromJson(<String, dynamic>{
        'user_id': 'u1',
        'symbol': 'XAUUSD',
        'session': 'newyork',
        'dow': 3.0, // extract() returns numeric
        'hour': 14.0,
        'pnl': 940.25,
        'n': 11,
        'win_rate': 0.5454,
      });

      expect(r.userId, 'u1');
      expect(r.symbol, 'XAUUSD');
      expect(r.session, 'newyork');
      expect(r.dayOfWeek, 3);
      expect(r.hour, 14);
      expect(r.pnl, 940.25);
      expect(r.trades, 11);
      expect(r.winRate, closeTo(0.5454, 1e-9));
    });

    test('accepts numeric strings, as PostgREST may deliver them', () {
      final PatternRow r = PatternRow.fromJson(<String, dynamic>{
        'user_id': 'u1',
        'symbol': 'EURUSD',
        'session': null,
        'dow': '2',
        'hour': '9',
        'pnl': '-310.40',
        'n': '12',
        'win_rate': '0.4166',
      });

      expect(r.pnl, -310.40);
      expect(r.trades, 12);
      expect(r.hour, 9);
      expect(r.session, isNull);
    });
  });

  group('PatternMetrics', () {
    test('an empty dataset yields an empty result, not an error', () {
      final PatternMetrics m =
          PatternMetrics.fromRows(const <PatternRow>[], PatternDimension.symbol);
      expect(m.isEmpty, isTrue);
      expect(m.journalTrades, 0);
      expect(m.worst, isNull);
      expect(m.best, isNull);
    });

    test('a single trade produces one slice carrying that trade', () {
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[row(pnl: -250, trades: 1, winRate: 0)],
        PatternDimension.symbol,
      );
      expect(m.metrics, hasLength(1));
      expect(m.metrics.single.pnl, -250);
      expect(m.metrics.single.trades, 1);
      expect(m.metrics.single.expectancy, -250);
      expect(m.journalTrades, 1);
    });

    test('groups rows sharing a symbol and sums their aggregates', () {
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[
          row(symbol: 'EURUSD', pnl: 100, trades: 10, winRate: 0.6),
          row(symbol: 'EURUSD', pnl: -40, trades: 5, winRate: 0.2),
          row(symbol: 'XAUUSD', pnl: 900, trades: 7, winRate: 0.8),
        ],
        PatternDimension.symbol,
      );

      expect(m.metrics, hasLength(2));
      final PatternMetric eurusd =
          m.metrics.firstWhere((PatternMetric x) => x.label == 'EURUSD');
      expect(eurusd.pnl, 60);
      expect(eurusd.trades, 15);
      // Weighted mean: (0.6*10 + 0.2*5) / 15 = 0.4667, NOT a plain average of
      // 0.6 and 0.2. Weighting by each row's own count is what makes this
      // equivalent to the GROUP BY SQL would have produced.
      expect(eurusd.winRate, closeTo(0.4666, 1e-4));
    });

    test('separates multiple symbols', () {
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[row(symbol: 'A'), row(symbol: 'B'), row(symbol: 'C', pnl: -10)],
        PatternDimension.symbol,
      );
      expect(
        m.metrics.map((PatternMetric x) => x.label).toSet(),
        <String>{'A', 'B', 'C'},
      );
    });

    test('separates multiple sessions', () {
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[
          row(session: 'london'),
          row(session: 'newyork'),
          row(session: 'asia', pnl: -5),
        ],
        PatternDimension.session,
      );
      expect(
        m.metrics.map((PatternMetric x) => x.label).toSet(),
        <String>{'London', 'Newyork', 'Asia'},
      );
    });

    test('an untagged session groups as Untagged instead of vanishing', () {
      // Dropping it would silently shrink the trader's sample size.
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[row(session: null, trades: 4), row(session: 'london')],
        PatternDimension.session,
      );
      expect(m.metrics, hasLength(2));
      expect(
        m.metrics.map((PatternMetric x) => x.label),
        contains(PatternLabels.untagged),
      );
      expect(m.journalTrades, 14);
    });

    test('separates multiple hours and labels them as clock times', () {
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[row(hour: 0), row(hour: 14), row(hour: 23, pnl: -3)],
        PatternDimension.hour,
      );
      expect(
        m.metrics.map((PatternMetric x) => x.label).toSet(),
        <String>{'00:00', '14:00', '23:00'},
      );
    });

    test('separates days of the week using the Postgres dow numbering', () {
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[
          row(dayOfWeek: 0), // Sunday
          row(dayOfWeek: 5, pnl: -9), // Friday
          row(dayOfWeek: 6),
        ],
        PatternDimension.dayOfWeek,
      );
      expect(
        m.metrics.map((PatternMetric x) => x.label).toSet(),
        <String>{'Sunday', 'Friday', 'Saturday'},
      );
    });

    test('drops rows with no value for the dimension and counts them', () {
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[row(hour: null, trades: 3), row(hour: 9)],
        PatternDimension.hour,
      );
      expect(m.metrics, hasLength(1));
      expect(m.droppedRows, 1);
      // The dropped row is excluded from the totals, so no figure claims to
      // describe a trade the slice cannot hold.
      expect(m.journalTrades, 10);
    });

    test('net P&L is already cost-inclusive, so nothing is subtracted again', () {
      // v_patterns sums trades.pnl, which tasks 2.1/2.2 write net of commission
      // and swap. Re-deriving a gross figure here would double-count the costs.
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[row(pnl: 60, trades: 15)],
        PatternDimension.symbol,
      );
      expect(m.metrics.single.pnl, 60);
      expect(m.journalPnl, 60);
    });

    test('orders by net P&L descending with a label tie-break', () {
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[
          row(symbol: 'AAA', pnl: 0),
          row(symbol: 'ZZZ', pnl: 0),
          row(symbol: 'MMM', pnl: 100),
        ],
        PatternDimension.symbol,
      );
      // MMM first on value; the two zero slices fall back to label order so the
      // list never reshuffles between builds.
      expect(m.metrics.map((PatternMetric x) => x.label), <String>['MMM', 'AAA', 'ZZZ']);
    });

    test('best and worst point at the ends of that order', () {
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[
          row(symbol: 'GOOD', pnl: 500),
          row(symbol: 'BAD', pnl: -500),
        ],
        PatternDimension.symbol,
      );
      expect(m.best?.label, 'GOOD');
      expect(m.worst?.label, 'BAD');
      expect(m.worst!.isNetNegative, isTrue);
    });

    test('handles hostile magnitudes without precision loss', () {
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[
          row(symbol: 'A', pnl: 1e12, trades: 1000, winRate: 1),
          row(symbol: 'B', pnl: -1e12, trades: 1000, winRate: 0),
        ],
        PatternDimension.symbol,
      );
      expect(m.metrics.first.pnl, 1e12);
      expect(m.metrics.last.pnl, -1e12);
      expect(m.metrics.first.expectancy, 1e9);
    });

    test('handles a very long symbol label without altering it', () {
      final String long = 'X' * 300;
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[row(symbol: long)],
        PatternDimension.symbol,
      );
      // The domain keeps the value verbatim; ellipsis is a rendering concern.
      expect(m.metrics.single.label.length, 300);
    });

    test('allDimensions covers exactly the four group columns in the view', () {
      final List<PatternMetrics> all =
          PatternMetrics.allDimensions(<PatternRow>[row()]);
      expect(
        all.map((PatternMetrics m) => m.dimension).toList(),
        PatternDimension.values,
      );
    });

    test('one trade in the journal still produces readable slices', () {
      // The insufficiency judgement belongs to the detector and the provider,
      // not to the aggregation â€” a one-trade journal is a valid, if thin, slice.
      final PatternMetrics m = PatternMetrics.fromRows(
        <PatternRow>[row(trades: 1)],
        PatternDimension.symbol,
      );
      expect(m.isEmpty, isFalse);
      expect(m.journalTrades, 1);
    });
  });
group('ranking', () {
    List<PatternMetric> sample() => PatternMetrics.fromRows(
          <PatternRow>[
            row(symbol: 'A', pnl: 100, trades: 10, winRate: 0.9),
            row(symbol: 'B', pnl: -300, trades: 30, winRate: 0.1),
            row(symbol: 'C', pnl: 0, trades: 20, winRate: 0.5),
          ],
          PatternDimension.symbol,
        ).metrics;

    test('ranks by trades', () {
      expect(
        PatternMetrics.ranked(sample(), PatternSort.trades, PatternDirection.ascending)
            .map((PatternMetric m) => m.label),
        <String>['A', 'C', 'B'],
      );
    });

    test('ranks by net P&L', () {
      expect(
        PatternMetrics.ranked(sample(), PatternSort.netPnl, PatternDirection.descending)
            .map((PatternMetric m) => m.label),
        <String>['A', 'C', 'B'],
      );
    });

    test('ranks by expectancy, which is what the default view uses', () {
      expect(
        PatternMetrics.ranked(sample(), PatternSort.expectancy, PatternDirection.ascending)
            .map((PatternMetric m) => m.label),
        <String>['B', 'C', 'A'],
      );
    });

    test('ranks by win rate', () {
      expect(
        PatternMetrics.ranked(sample(), PatternSort.winRate, PatternDirection.descending)
            .map((PatternMetric m) => m.label),
        <String>['A', 'C', 'B'],
      );
    });

    test('reverses cleanly with the direction', () {
      expect(
        PatternMetrics.ranked(sample(), PatternSort.trades, PatternDirection.descending)
            .first
            .label,
        'B',
      );
    });

    test('does not mutate the source list', () {
      final List<PatternMetric> original = sample();
      PatternMetrics.ranked(original, PatternSort.trades, PatternDirection.ascending);
      expect(original.first.label, 'A');
    });

    test('is deterministic across repeated calls', () {
      final List<String> a = PatternMetrics.ranked(
        sample(),
        PatternSort.expectancy,
        PatternDirection.ascending,
      ).map((PatternMetric m) => m.label).toList();
      final List<String> b = PatternMetrics.ranked(
        sample(),
        PatternSort.expectancy,
        PatternDirection.ascending,
      ).map((PatternMetric m) => m.label).toList();
      expect(a, b);
    });

    test('breaks ties on the label so equal values never reshuffle', () {
      final List<PatternMetric> tied = PatternMetrics.fromRows(
        <PatternRow>[row(symbol: 'ZZZ'), row(symbol: 'AAA')],
        PatternDimension.symbol,
      ).metrics;
      final List<PatternMetric> forward =
          PatternMetrics.ranked(tied, PatternSort.trades, PatternDirection.ascending);
      final List<PatternMetric> backward =
          PatternMetrics.ranked(tied, PatternSort.trades, PatternDirection.descending);
      // Value order is meaningless when the values are identical, so the label
      // tie-break keeps the same order in both directions.
      expect(forward.map((PatternMetric m) => m.label), <String>['AAA', 'ZZZ']);
      expect(backward.map((PatternMetric m) => m.label), <String>['AAA', 'ZZZ']);
    });
  });

  group('labels', () {
    test('capitalises session names', () {
      expect(PatternLabels.session('newyork'), 'Newyork');
    });

    test('names an untagged session', () {
      expect(PatternLabels.session(null), PatternLabels.untagged);
      expect(PatternLabels.session('   '), PatternLabels.untagged);
    });

    test('passes a symbol through untouched apart from trimming', () {
      expect(PatternLabels.symbol(' XAUUSD '), 'XAUUSD');
      expect(PatternLabels.symbol(null), PatternLabels.untagged);
    });

    test('pads hours to a clock label', () {
      expect(PatternLabels.hour(0), '00:00');
      expect(PatternLabels.hour(9), '09:00');
    });

    test('falls back for an out-of-range day rather than throwing', () {
      expect(PatternLabels.dayOfWeek(0), 'Sunday');
      expect(PatternLabels.dayOfWeek(6), 'Saturday');
      expect(PatternLabels.dayOfWeek(9), 'Day 9');
    });
  });
}
