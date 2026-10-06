import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/signal.dart';
import 'package:tradeguard/core/services/services.dart';
import 'package:tradeguard/features/replay/domain/price_bar.dart';
import 'package:tradeguard/features/replay/domain/price_series.dart';
import 'package:tradeguard/features/replay/domain/price_series_request.dart';
import 'package:tradeguard/features/replay/replay_providers.dart';
import 'package:tradeguard/features/signals/data/signal_repository.dart';
import 'package:tradeguard/features/signals/domain/volatility_score.dart';
import 'package:tradeguard/features/signals/signal_providers.dart';
import 'package:tradeguard/features/signals/widgets/signal_stats_card.dart';

/// A repository that answers with whatever it was handed, so the feed can be
/// driven without a backend — the same shape as the fake in
/// `signal_feed_test.dart`, kept local so each file stays self-contained.
class FakeSignalRepository implements SignalRepository {
  FakeSignalRepository({this.signals = const <Signal>[]});

  final List<Signal> signals;

  @override
  bool get isStubbed => true;

  @override
  Future<List<Signal>> fetchSignals({int limit = 100}) async =>
      List<Signal>.unmodifiable(signals.take(limit));
}

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

/// A ledger big enough to clear the reporting floor: 12 closed calls, 2
/// still open — so the ledger section renders its numbers beside the radar.
List<Signal> reportableLedger() => <Signal>[
      signal(id: 'a1'),
      signal(id: 'a2'),
      for (int i = 0; i < 8; i++)
        signal(id: 'w$i', status: SignalStatus.closed, resultPips: 60),
      for (int i = 0; i < 4; i++)
        signal(id: 'l$i', status: SignalStatus.closed, resultPips: -17.5),
    ];

/// Doji bars whose true range at index i is exactly [rangeAt] — same
/// fixture contract as `volatility_score_test.dart`, so the provider tests
/// reuse the domain's guarantees instead of re-deriving them.
List<PriceBar> barsFixture(int n, double Function(int i) rangeAt) => <PriceBar>[
      for (int i = 0; i < n; i++)
        PriceBar(
          time: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
          open: 100,
          high: 100 + rangeAt(i),
          low: 100,
          close: 100,
        ),
    ];

const PriceSeriesRequest request = PriceSeriesRequest(
  symbol: 'XAUUSD',
  timeframe: ReplayTimeframe.h1,
);

PriceSeries seriesOf(List<PriceBar> bars) =>
    PriceSeries(request: request, bars: bars);

ReplayBarsState readyState(List<PriceBar> bars, {bool stubbed = true}) =>
    ReplayBarsState(
      status: ReplayBarsStatus.ready,
      series: seriesOf(bars),
      isStubbed: stubbed,
    );

ProviderContainer createContainer(
        {List<Override> overrides = const <Override>[],}) {
  final ProviderContainer container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('radar providers', () {
    test('the radar measures the first series in the repository catalogue',
        () {
      final ProviderContainer container = createContainer();
      final PriceSeriesRequest series =
          container.read(signalRadarSeriesProvider);
      expect(series, Services.instance.prices.supportedSeries.first);
      // Mock mode's catalogue opens with gold — the pair this product is
      // built around, and the one the provenance line will name.
      expect(series.symbol, 'XAUUSD');
    });

    test('no score while bars are still loading', () {
      final ProviderContainer container = createContainer(
        overrides: <Override>[
          signalRadarBarsProvider.overrideWithValue(const ReplayBarsState()),
        ],
      );
      expect(container.read(signalVolatilityProvider), isNull);
    });

    test('no score for a series below the window floor', () {
      final ProviderContainer container = createContainer(
        overrides: <Override>[
          signalRadarBarsProvider.overrideWithValue(
            readyState(barsFixture(10, (int i) => 2.0)),
          ),
        ],
      );
      expect(container.read(signalVolatilityProvider), isNull);
    });

    test('a ready series scores exactly what the domain computes', () {
      final List<PriceBar> market = barsFixture(60, (int i) => i.toDouble());
      final ProviderContainer container = createContainer(
        overrides: <Override>[
          signalRadarBarsProvider.overrideWithValue(readyState(market)),
        ],
      );
      final VolatilityScore? score = container.read(signalVolatilityProvider);
      expect(score, isNotNull);
      expect(score!.score, VolatilityScore.of(market)!.score);
      expect(score.band, VolatilityBand.high);
    });

    test('a failed refresh that still carries bars keeps scoring', () {
      // The state replay calls a stale failure: the reload did not land, but
      // the series on hand is real. Dropping it would blank a working radar
      // because of a network blip.
      final ProviderContainer container = createContainer(
        overrides: <Override>[
          signalRadarBarsProvider.overrideWithValue(
            ReplayBarsState(
              status: ReplayBarsStatus.error,
              series: seriesOf(barsFixture(60, (int i) => i.toDouble())),
              isStubbed: true,
            ),
          ),
        ],
      );
      expect(container.read(signalVolatilityProvider), isNotNull);
    });

    test('stats carry the radar beside the untouched ledger', () async {
      final ProviderContainer container = createContainer(
        overrides: <Override>[
          signalFeedProvider.overrideWith(
            (Ref ref) => SignalFeedNotifier(
              FakeSignalRepository(signals: reportableLedger()),
            ),
          ),
          signalRadarBarsProvider.overrideWithValue(
            readyState(barsFixture(60, (int i) => i.toDouble())),
          ),
        ],
      );
      await container.read(signalFeedProvider.notifier).refresh();

      final stats = container.read(signalStatsProvider);
      expect(stats.closed, 12);
      expect(stats.winRate, isNotNull);
      expect(stats.volatility, isNotNull);
      expect(
        stats.volatility!.score,
        container.read(signalVolatilityProvider)!.score,
      );
    });

    test('an unmeasured radar stays null through the stats', () async {
      final ProviderContainer container = createContainer(
        overrides: <Override>[
          signalFeedProvider.overrideWith(
            (Ref ref) => SignalFeedNotifier(FakeSignalRepository()),
          ),
          signalRadarBarsProvider.overrideWithValue(const ReplayBarsState()),
        ],
      );
      await container.read(signalFeedProvider.notifier).refresh();

      final stats = container.read(signalStatsProvider);
      expect(stats.total, 0);
      expect(stats.volatility, isNull);
    });
  });

  group('SignalStatsCard — radar states', () {
    /// The card on its own, with the feed and the bar read injected so each
    /// state can be driven without a backend or a timer.
    Widget card({ReplayBarsState? bars, List<Signal>? signals}) =>
        ProviderScope(
          overrides: <Override>[
            signalRadarBarsProvider
                .overrideWithValue(bars ?? const ReplayBarsState()),
            signalFeedProvider.overrideWith(
              (Ref ref) => SignalFeedNotifier(
                FakeSignalRepository(signals: signals ?? reportableLedger()),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: const <Widget>[SignalStatsCard()],
              ),
            ),
          ),
        );

    testWidgets('a measured radar shows score, band, provenance and ledger',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        card(bars: readyState(barsFixture(60, (int i) => i.toDouble()))),
      );
      await tester.pumpAndSettle();

      expect(find.text('VOLATILITY RADAR'), findsOneWidget);
      expect(find.text(VolatilityBand.high.label), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('XAUUSD H1'), findsOneWidget);
      expect(find.textContaining('SYNTHETIC DEMO'), findsOneWidget);
      expect(find.textContaining('not a prediction'), findsOneWidget);
      // The ledger renders beside the radar, not instead of it.
      expect(find.text('VERIFIED LEDGER'), findsOneWidget);
      expect(find.textContaining('closed of 14 posted'), findsOneWidget);
    });

    testWidgets('loading bars say measuring and leave the ledger intact',
        (WidgetTester tester) async {
      await tester.pumpWidget(card());
      await tester.pumpAndSettle();

      expect(find.text('Measuring volatility…'), findsOneWidget);
      // Never a meter without a score behind it.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('VERIFIED LEDGER'), findsOneWidget);
      expect(find.textContaining('closed of 14 posted'), findsOneWidget);
    });

    testWidgets('a failed read shows the closed-set failure wording',
        (WidgetTester tester) async {
      const ReplayBarsState failed =
          ReplayBarsState(status: ReplayBarsStatus.error);
      await tester.pumpWidget(card(bars: failed));
      await tester.pumpAndSettle();

      expect(find.text(failed.failure.message), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a too-short series says not measured, with the count',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        card(bars: readyState(barsFixture(10, (int i) => 2.0))),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Not enough bars to measure volatility'),
        findsOneWidget,
      );
      expect(find.textContaining('10 available'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a stale failure keeps the reading and labels it',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        card(
          bars: ReplayBarsState(
            status: ReplayBarsStatus.error,
            series: seriesOf(barsFixture(60, (int i) => i.toDouble())),
            isStubbed: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(VolatilityBand.high.label), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        find.text('Latest refresh failed — showing the last measured reading.'),
        findsOneWidget,
      );
    });

    testWidgets('the radar never invents newswire drivers',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        card(bars: readyState(barsFixture(60, (int i) => i.toDouble()))),
      );
      await tester.pumpAndSettle();

      // The placeholder this screen used to carry claimed "USD CPI" and a
      // DXY move beside a hardcoded 64. Fabricated market context must not
      // come back anywhere on this card.
      expect(find.textContaining('CPI'), findsNothing);
      expect(find.textContaining('DXY'), findsNothing);
      expect(find.textContaining('Top drivers'), findsNothing);
    });
  });
}
