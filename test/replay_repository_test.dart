import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/features/replay/data/mock_price_bar_repository.dart';
import 'package:tradeguard/features/replay/data/price_bar_repository.dart';
import 'package:tradeguard/features/replay/domain/price_bar.dart';
import 'package:tradeguard/features/replay/domain/price_series.dart';
import 'package:tradeguard/features/replay/domain/price_series_request.dart';

const PriceSeriesRequest xauH1 =
    PriceSeriesRequest(symbol: 'XAUUSD', timeframe: ReplayTimeframe.h1);

/// One cached row for a given day and close.
Map<String, dynamic> _row(String day, double close) => <String, dynamic>{
      't': '${day}T00:00:00Z',
      'o': close - 0.25,
      'h': close + 0.5,
      'l': close - 0.75,
      'c': close,
    };

void main() {
  group('PriceBar parsing', () {
    test('reads the cached jsonb shape', () {
      final List<PriceBar> bars = PriceBar.fromCacheList(<Object?>[
        <String, dynamic>{
          't': '2024-01-02T00:00:00Z',
          'o': 2345.5,
          'h': 2350.0,
          'l': 2340.0,
          'c': 2348.25,
        },
      ]);
      expect(bars, hasLength(1));
      expect(bars.first.close, 2348.25);
      expect(bars.first.time.isUtc, isTrue);
    });

    test("reads TwelveData's positional tuples too", () {
      // The function normalises to the short-key shape, but a future producer forwarding raw provider
      // rows must not silently produce an empty chart.
      final List<PriceBar> bars = PriceBar.fromCacheList(<Object?>[
        <Object?>['2024-01-02T00:00:00', '2345.5', '2350', '2340', '2348.25'],
      ]);
      expect(bars.single.open, 2345.5);
    });

    test('sorts newest-first provider output into chronological order', () {
      // THE regression this guards: the engine walks forward in time, so a reversed series would fill at
      // a price that had not happened yet — a backtest nobody could have traded.
      final List<PriceBar> bars = PriceBar.fromCacheList(<Object?>[
        _row('2024-01-03', 3),
        _row('2024-01-01', 1),
        _row('2024-01-02', 2),
      ]);
      expect(bars.map((PriceBar b) => b.close), <double>[1, 2, 3]);
    });

    test('a duplicate timestamp collapses to the last restatement', () {
      final List<PriceBar> bars = PriceBar.fromCacheList(<Object?>[
        _row('2024-01-02', 1.5),
        _row('2024-01-02', 9.75),
      ]);
      expect(bars, hasLength(1));
      expect(bars.single.close, 9.75);
    });

    test('malformed rows are dropped and the rest survive', () {
      final List<PriceBar> bars = PriceBar.fromCacheList(<Object?>[
        _row('2024-01-01', 1),
        'not an object',
        <String, dynamic>{'t': '2024-01-02'},
        _row('2024-01-03', 3),
      ]);
      expect(bars.map((PriceBar b) => b.close), <double>[1, 3]);
    });

    test('an inconsistent bar is refused', () {
      // A high below the low is a chart the market cannot have produced.
      expect(
        PriceBar.fromCacheList(<Object?>[
          <String, dynamic>{
            't': '2024-01-02T00:00:00Z',
            'o': 10,
            'h': 1,
            'l': 20,
            'c': 5,
          },
        ]),
        isEmpty,
      );
    });

    test('non-finite numbers never become a price', () {
      expect(
        PriceBar.fromCacheList(<Object?>[
          <String, dynamic>{
            't': '2024-01-02T00:00:00Z',
            'o': 1,
            'h': double.nan,
            'l': 0,
            'c': 1,
          },
        ]),
        isEmpty,
      );
    });

    test('a non-list payload is empty rather than an error', () {
      expect(PriceBar.fromCacheList(null), isEmpty);
      expect(PriceBar.fromCacheList('nope'), isEmpty);
      expect(PriceBar.fromCacheList(<Object?>[null, 5, <int>[1]]), isEmpty);
    });

    test('round-trips through the cached shape', () {
      final PriceBar original = PriceBar(
        time: DateTime.utc(2024, 1, 2),
        open: 1,
        high: 2,
        low: 0.5,
        close: 1.5,
      );
      final PriceBar? back = PriceBar.fromCacheList(<Object?>[
        original.toCacheJson(),
      ]).singleOrNull;
      expect(back, isNotNull);
      expect(back!.close, 1.5);
      expect(back.time, original.time);
    });
  });

  group('PriceSeries metadata', () {
    test('reports bar count, span and density', () {
      final PriceSeries series = PriceSeries(
        request: xauH1,
        bars: <PriceBar>[
          for (int i = 0; i < 24; i++)
            PriceBar(
              time: DateTime.utc(2024, 1, 2).add(Duration(hours: i)),
              open: 1,
              high: 2,
              low: 0.5,
              close: 1.5,
            ),
        ],
        asOf: DateTime.utc(2024, 1, 3),
      );
      expect(series.barCount, 24);
      expect(series.span.inHours, 23);
      expect(series.barsPerDay, greaterThan(20));
      expect(series.lastClose, 1.5);
      expect(series.extremes, isNotNull);
    });

    test('an unknown age is null rather than silently fresh', () {
      // The screen must be able to say "age unknown" instead of implying a live feed.
      final PriceSeries series = PriceSeries(
        request: xauH1,
        bars: <PriceBar>[
          PriceBar(
            time: DateTime.utc(2024, 1, 2),
            open: 1,
            high: 2,
            low: 0.5,
            close: 1.5,
          ),
        ],
      );
      expect(series.ageAt(DateTime.utc(2024, 1, 3)), isNull);
    });

    test('a future stamp reads as brand new rather than negative', () {
      final PriceSeries series = PriceSeries(
        request: xauH1,
        bars: const <PriceBar>[],
        asOf: DateTime.utc(2030),
      );
      expect(series.ageAt(DateTime.utc(2024)), Duration.zero);
    });

    test('extremes on an empty series are null so the chart can branch', () {
      expect(PriceSeries.empty(xauH1).extremes, isNull);
      expect(PriceSeries.empty(xauH1).lastClose, isNull);
      expect(PriceSeries.empty(xauH1).isEmpty, isTrue);
    });
  });

  group('the request key', () {
    test('compares by value so the provider is not refetched per rebuild', () {
      expect(
        const PriceSeriesRequest(symbol: 'xauusd', timeframe: ReplayTimeframe.h1),
        xauH1,
      );
      expect(
        const PriceSeriesRequest(symbol: 'XAUUSD', timeframe: ReplayTimeframe.h1)
            .hashCode,
        xauH1.hashCode,
      );
      expect(
        xauH1,
        isNot(
          const PriceSeriesRequest(symbol: 'EURUSD', timeframe: ReplayTimeframe.h1),
        ),
      );
    });

    test('the cache key matches the prices_cache primary key', () {
      expect(xauH1.cacheKey, 'XAUUSD|1h');
    });

    test('timeframes round-trip through the wire value', () {
      for (final ReplayTimeframe t in ReplayTimeframe.values) {
        expect(ReplayTimeframe.fromWire(t.wire), t);
      }
      expect(ReplayTimeframe.fromWire('nonsense'), ReplayTimeframe.h1);
    });
  });

  group('the mock repository', () {
    test('labels its own output as synthetic', () {
      // An unlabelled generated chart is indistinguishable from the market, which for a backtest is the
      // single most misleading thing this product could ship.
      final MockPriceBarRepository repo = MockPriceBarRepository(barCount: 30);
      expect(repo.isStubbed, isTrue);
      expect(repo.supportedSeries, isNotEmpty);
    });

    test('marks its series as demo data', () async {
      final PriceSeries series =
          await MockPriceBarRepository(barCount: 30).fetchSeries(xauH1);
      expect(series.isStubbed, isTrue);
      expect(series.source, PriceSeriesSource.demo);
      expect(series.source.isDemo, isTrue);
      expect(series.source.label, contains('Synthetic'));
    });

    test('is deterministic for the same symbol', () async {
      final PriceSeries a =
          await MockPriceBarRepository(barCount: 40).fetchSeries(xauH1);
      final PriceSeries b =
          await MockPriceBarRepository(barCount: 40).fetchSeries(xauH1);
      expect(
        a.bars.map((PriceBar x) => x.close).toList(),
        b.bars.map((PriceBar x) => x.close).toList(),
      );
    });

    test('different symbols get different walks', () async {
      const PriceSeriesRequest eurusd =
          PriceSeriesRequest(symbol: 'EURUSD', timeframe: ReplayTimeframe.h1);
      final PriceSeries gold =
          await MockPriceBarRepository(barCount: 40).fetchSeries(xauH1);
      final PriceSeries euro =
          await MockPriceBarRepository(barCount: 40).fetchSeries(eurusd);
      expect(
        gold.bars.map((PriceBar x) => x.close).toList(),
        isNot(equals(euro.bars.map((PriceBar x) => x.close).toList())),
      );
    });

    test('generates well-formed bars in chronological order', () async {
      final PriceSeries series =
          await MockPriceBarRepository(barCount: 120).fetchSeries(xauH1);
      expect(series.barCount, 120);
      for (final PriceBar b in series.bars) {
        expect(b.isWellFormed, isTrue);
      }
      for (int i = 1; i < series.bars.length; i++) {
        expect(
          series.bars[i].time.isAfter(series.bars[i - 1].time),
          isTrue,
          reason: 'bar $i must be later than bar ${i - 1}',
        );
      }
    });

    test('respects the timeframe spacing', () async {
      const PriceSeriesRequest h4 =
          PriceSeriesRequest(symbol: 'XAUUSD', timeframe: ReplayTimeframe.h4);
      final PriceSeries series =
          await MockPriceBarRepository(barCount: 10).fetchSeries(h4);
      expect(
        series.bars[1].time.difference(series.bars[0].time),
        const Duration(hours: 4),
      );
    });

    test('produces a range the replay can actually work with', () async {
      // A generator whose prices never revisit a level would make every setup fill at bar zero, so the
      // feature would look broken while being technically correct.
      final PriceSeries series =
          await MockPriceBarRepository(barCount: 200).fetchSeries(xauH1);
      final Set<String> distinct = series.bars
          .map((PriceBar b) => b.close.toStringAsFixed(2))
          .toSet();
      expect(distinct.length, greaterThan(20));
    });

    test('reports its own failure vocabulary rather than returning empty', () async {
      final MockPriceBarRepository repo = MockPriceBarRepository(barCount: 10)
        ..unavailable.add('XAUUSD');
      await expectLater(
        repo.fetchSeries(xauH1),
        throwsA(
          isA<PriceBarException>().having(
            (PriceBarException e) => e.failure,
            'failure',
            PriceBarFailure.unknownSeries,
          ),
        ),
      );
    });

    test('a transport failure throws instead of looking like "no history"', () async {
      // Returning an empty list here would render as "this symbol has no bars", which is a different and
      // misleading claim from "the read failed".
      final MockPriceBarRepository repo = MockPriceBarRepository(barCount: 10)
        ..failing = true;
      await expectLater(
        repo.fetchSeries(xauH1),
        throwsA(isA<PriceBarException>()),
      );
    });

    test('a repeat read returns the same series rather than regenerating', () async {
      // Value equality, not identity: the mock caches the generated bars, but `fetchSeries` re-wraps them
      // in a fresh unmodifiable list per call. What matters to a test is that the PRICES are stable — a
      // regenerated walk would make the widget tests flaky and a replay unreproducible.
      final MockPriceBarRepository repo = MockPriceBarRepository(barCount: 30);
      final PriceSeries first = await repo.fetchSeries(xauH1);
      final PriceSeries second = await repo.fetchSeries(xauH1);
      expect(
        first.bars.map((PriceBar b) => b.close).toList(),
        second.bars.map((PriceBar b) => b.close).toList(),
      );
      expect(second.bars.length, first.bars.length);
    });
  });
}