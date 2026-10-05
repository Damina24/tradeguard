import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/trade.dart';
import 'package:tradeguard/features/replay/data/price_bar_repository.dart';
import 'package:tradeguard/features/replay/domain/price_bar.dart';
import 'package:tradeguard/features/replay/domain/price_series.dart';
import 'package:tradeguard/features/replay/domain/price_series_request.dart';
import 'package:tradeguard/features/replay/domain/replay_result.dart';
import 'package:tradeguard/features/replay/domain/replay_scan.dart';
import 'package:tradeguard/features/replay/domain/replay_setup.dart';
import 'package:tradeguard/features/replay/presentation/replay_screen.dart';
import 'package:tradeguard/features/replay/replay_providers.dart';
import 'package:tradeguard/features/replay/widgets/replay_chart.dart';
import 'package:tradeguard/features/replay/widgets/replay_controls.dart';
import 'package:tradeguard/features/replay/widgets/replay_scan_card.dart';
import 'package:tradeguard/features/replay/widgets/replay_setup_form.dart';
import 'package:tradeguard/features/replay/widgets/replay_state_view.dart';
import 'package:tradeguard/features/replay/widgets/replay_verdict_card.dart';

const PriceSeriesRequest xauH1 =
    PriceSeriesRequest(symbol: 'XAUUSD', timeframe: ReplayTimeframe.h1);

/// A gently rising series, so a setup has somewhere to go.
List<PriceBar> risingBars({int count = 60}) => <PriceBar>[
      for (int i = 0; i < count; i++)
        PriceBar(
          time: DateTime.utc(2024, 1, 2).add(Duration(minutes: i)),
          open: 100 + i * 0.5,
          high: 101 + i * 0.5,
          low: 99 + i * 0.5,
          close: 100 + i * 0.5 + (i % 3) * 0.2,
        ),
    ];

/// Entry 100, stop 97, target 106: a 3-point risk against a 6-point reward, i.e. exactly 1R / 2R.
const ReplaySetup longSetup = ReplaySetup(
  symbol: 'XAUUSD',
  direction: TradeDirection.long,
  entry: 100,
  stop: 97,
  target: 106,
  lots: 1,
  balance: 10000,
);

/// A repository whose answer a test decides.
class FakeBars implements PriceBarRepository {
  FakeBars({this.bars, this.failure, this.isStubbed = false});

  final List<PriceBar>? bars;
  final PriceBarFailure? failure;
  @override
  final bool isStubbed;

  @override
  List<PriceSeriesRequest> get supportedSeries =>
      const <PriceSeriesRequest>[xauH1];

  @override
  Future<PriceSeries> fetchSeries(PriceSeriesRequest request) async {
    final PriceBarFailure? f = failure;
    if (f != null) throw PriceBarException(f);
    return PriceSeries(
      request: request,
      bars: bars ?? const <PriceBar>[],
      asOf: DateTime.now().toUtc(),
      source: isStubbed ? PriceSeriesSource.demo : PriceSeriesSource.cache,
      isStubbed: isStubbed,
    );
  }
}

/// Never answers, so the loading state can be held open.
class PendingBars implements PriceBarRepository {
  @override
  bool get isStubbed => false;

  @override
  List<PriceSeriesRequest> get supportedSeries =>
      const <PriceSeriesRequest>[xauH1];

  @override
  Future<PriceSeries> fetchSeries(PriceSeriesRequest request) =>
      Completer<PriceSeries>().future;
}

/// Wraps [child] in the providers the screen reads.
///
/// The `Scaffold` is not decoration: it supplies the `Material` ancestor that `ChoiceChip`, `Slider`
/// and `InkWell` require. `MaterialApp(home: child)` alone does not, and several of these widgets are
/// exercised outside a screen that would provide one.
///
/// Pass [state] to hand the screen an ALREADY-RESOLVED read. That is the default for the screen tests
/// because a widget test's fake-async clock does not reliably flush the notifier's first microtask,
/// which would leave every ready/empty/error assertion testing the loading state instead of the one it
/// names. Pass [repository] to drive the notifier itself when the loading path is what is under test.
Widget _app(
  Widget child, {
  PriceBarRepository? repository,
  ReplayBarsState? state,
  ReplaySetup? setup,
  int cursor = 0,
}) {
  final PriceBarRepository repo = repository ?? FakeBars(bars: risingBars());
  return ProviderScope(
    overrides: <Override>[
      // `StateProvider` has no `overrideWithValue` in Riverpod 2.x, so the initial value comes from a
      // one-line builder.
      replayBarsProvider.overrideWith(
        (Ref ref, PriceSeriesRequest request) =>
            ReplayBarsNotifier(repo, xauH1),
      ),
      if (state != null) selectedBarsProvider.overrideWithValue(state),
      priceCatalogueProvider.overrideWithValue(repo.supportedSeries),
      replaySetupProvider.overrideWith((Ref ref) => setup),
      replayCursorProvider.overrideWith((Ref ref) => cursor),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

/// A resolved read for [bars], labelled as cached market data.
ReplayBarsState cached(List<PriceBar> bars) => ReplayBarsState(
      status: bars.isEmpty
          ? ReplayBarsStatus.empty
          : (bars.length < ReplayBarsNotifier.minimumBars
              ? ReplayBarsStatus.tooShort
              : ReplayBarsStatus.ready),
      series: PriceSeries(
        request: xauH1,
        bars: bars,
        asOf: DateTime.now().toUtc(),
      ),
    );

/// A resolved read that failed, optionally keeping a previously-loaded series.
ReplayBarsState failed(PriceBarFailure failure, {List<PriceBar>? keep}) =>
    ReplayBarsState(
      status: ReplayBarsStatus.error,
      failure: switch (failure) {
        PriceBarFailure.notConfigured => ReplayBarFailure.notConfigured,
        PriceBarFailure.unreachable => ReplayBarFailure.unreachable,
        PriceBarFailure.failed => ReplayBarFailure.failed,
        PriceBarFailure.unknownSeries => ReplayBarFailure.unknownSeries,
        PriceBarFailure.warming => ReplayBarFailure.warming,
      },
      series: keep == null
          ? null
          : PriceSeries(request: xauH1, bars: keep, asOf: DateTime.now().toUtc()),
    );

/// Lets a pending future complete, then settles the frame queue.
///
/// The extra pump is not paranoia: `pumpAndSettle` alone can return before the repository's future
/// has run its first microtask, because at that point nothing has scheduled a frame for it to wait
/// on. That leaves the notifier in `loading` and makes every ready-state assertion fail for a reason
/// that has nothing to do with what they are testing.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

/// Pumps at a given surface size, so a layout regression is caught here rather than on a device.
Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(child);
  await _settle(tester);
}

void _noop(int _) {}

/// The bar the form defaults to: the first of the rising fixture.
final PriceBar _firstBar = risingBars().first;

/// A pre-built empty scan: `ReplayScan.empty` is a factory, so it cannot sit in a `const` tree.
final ReplayScan _emptyScan = ReplayScan.empty();

/// Resolved states the screen tests hand the tree directly.
final ReplayBarsState _failed = failed(PriceBarFailure.unreachable);
final ReplayBarsState _notConfigured = failed(PriceBarFailure.notConfigured);

final ReplayBarsState _synthetic = ReplayBarsState(
  status: ReplayBarsStatus.ready,
  isStubbed: true,
  series: PriceSeries(
    request: xauH1,
    bars: risingBars(),
    asOf: DateTime.now().toUtc(),
    source: PriceSeriesSource.demo,
    isStubbed: true,
  ),
);

/// A refresh that failed while a usable series was already on screen.
final ReplayBarsState _staleFailure = failed(
  PriceBarFailure.unreachable,
  keep: risingBars(),
);

void main() {
  group('the verdict card states each outcome in its own words', () {
    testWidgets('no setup yet invites one', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ReplayVerdictCard(setup: null, result: null)),
        ),
      );
      expect(find.textContaining('SET UP A TRADE'), findsOneWidget);
    });

    testWidgets('never filled is NOT shown as a loss',
        (WidgetTester tester) async {
      // The regression: rendering this as a red -1R would invent a trade that never happened.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReplayVerdictCard(
              setup: longSetup,
              result: ReplayResult.notFilled(longSetup),
              visibleBars: 40,
            ),
          ),
        ),
      );
      expect(find.textContaining('NEVER REACHED'), findsOneWidget);
      expect(find.textContaining('not a loss'), findsOneWidget);
      expect(find.textContaining('STOP HIT'), findsNothing);
    });

    testWidgets('an unresolved position is labelled, not presented as a result',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReplayVerdictCard(
              setup: longSetup,
              result: ReplayResult(
                setup: longSetup,
                status: ReplayStatus.unresolved,
                fillIndex: 0,
                fillPrice: 100,
                exitPrice: 103,
                barsHeld: 12,
                mfeR: 0.6,
                maeR: -0.2,
              ),
              visibleBars: 40,
            ),
          ),
        ),
      );
      expect(find.textContaining('STILL OPEN'), findsOneWidget);
      expect(find.textContaining('not a closed result'), findsOneWidget);
    });

    testWidgets('a resolved target is named as a target',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReplayVerdictCard(
              setup: longSetup,
              result: ReplayResult(
                setup: longSetup,
                status: ReplayStatus.targetHit,
                fillIndex: 0,
                fillPrice: 100,
                exitIndex: 14,
                exitPrice: 106,
                barsHeld: 14,
                mfeR: 1.2,
                maeR: -0.6,
              ),
              visibleBars: 40,
            ),
          ),
        ),
      );
      expect(find.textContaining('TARGET REACHED'), findsOneWidget);
      expect(find.textContaining('+2.00R'), findsOneWidget);
      // The evidence rows make the verdict auditable bar by bar.
      expect(find.text('Filled at'), findsOneWidget);
      expect(find.text('MFE'), findsOneWidget);
      expect(find.text('MAE'), findsOneWidget);
    });

    testWidgets('an unscored result shows a dash, not a zero',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReplayVerdictCard(
              setup: longSetup,
              result: ReplayResult(
                setup: longSetup,
                status: ReplayStatus.targetHit,
              ),
            ),
          ),
        ),
      );
      // A zero would read as a verdict about a trade nobody assessed.
      expect(find.textContaining('0.00R'), findsNothing);
    });

    testWidgets('an invalid setup shows its own reason',
        (WidgetTester tester) async {
      const ReplaySetup inverted = ReplaySetup(
        symbol: 'XAUUSD',
        direction: TradeDirection.long,
        entry: 100,
        stop: 105,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReplayVerdictCard(
              setup: inverted,
              result: ReplayResult.invalid(inverted),
            ),
          ),
        ),
      );
      expect(find.textContaining('CANNOT BE REPLAYED'), findsOneWidget);
      expect(find.textContaining('BELOW'), findsOneWidget);
    });
  });

  group('the scan card refuses to state a rate it cannot support', () {
    testWidgets('with no setup it says so', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReplayScanCard(scan: _emptyScan, hasSetup: false),
          ),
        ),
      );
      expect(find.textContaining('NO SWEEP YET'), findsOneWidget);
    });

    testWidgets('below the floor it prints no rate at all',
        (WidgetTester tester) async {
      // THE regression: a confident win rate off three correlated bars is not a weak statistic, it is a
      // misleading one.
      final ReplayScan thin = ReplayScan(
        results: <ReplayResult>[
          for (int i = 0; i < 3; i++)
            ReplayResult(
              setup: longSetup,
              status: ReplayStatus.targetHit,
              fillIndex: i,
              exitIndex: i + 2,
              exitPrice: 106,
            ),
        ],
        minimumTrades: 10,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReplayScanCard(scan: thin, hasSetup: true),
          ),
        ),
      );
      expect(find.textContaining('NOT ENOUGH TRADES'), findsOneWidget);
      expect(find.text('WIN RATE'), findsNothing);
      expect(find.text('100.0%'), findsNothing);
      // The count is still printed, because "not enough data" with a number is actionable.
      expect(find.textContaining('3 of the 3'), findsOneWidget);
    });

    testWidgets('above the floor it prints the rates and the caveat',
        (WidgetTester tester) async {
      final ReplayScan ample = ReplayScan(
        results: <ReplayResult>[
          for (int i = 0; i < 12; i++)
            ReplayResult(
              setup: longSetup,
              status: i.isEven ? ReplayStatus.targetHit : ReplayStatus.stopHit,
              fillIndex: i,
              exitIndex: i + 2,
              exitPrice: i.isEven ? 106 : 97,
            ),
        ],
        minimumTrades: 10,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReplayScanCard(scan: ample, hasSetup: true),
          ),
        ),
      );
      expect(find.textContaining('EVERY BAR TESTED'), findsOneWidget);
      expect(find.text('50.0%'), findsOneWidget);
      expect(find.textContaining('correlated'), findsOneWidget);
      // All three outcome categories are always printed, so the counts can be checked against each
      // other rather than inferred.
      expect(find.text('Targets reached'), findsOneWidget);
      expect(find.text('Stops hit'), findsOneWidget);
      expect(find.text('Still open at the end'), findsOneWidget);
    });

    testWidgets('a flawless run shows a dash for PF, never infinity',
        (WidgetTester tester) async {
      final ReplayScan flawless = ReplayScan(
        results: <ReplayResult>[
          for (int i = 0; i < 12; i++)
            ReplayResult(
              setup: longSetup,
              status: ReplayStatus.targetHit,
              fillIndex: i,
              exitIndex: i + 2,
              exitPrice: 106,
            ),
        ],
        minimumTrades: 10,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReplayScanCard(scan: flawless, hasSetup: true),
          ),
        ),
      );
      expect(find.text('PF'), findsOneWidget);
      expect(find.text('∞'), findsNothing);
    });
  });

  group('the transport disables rather than lying', () {
    testWidgets('step-back is disabled at the first bar',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          const ReplayControls(
            cursor: 0,
            total: 20,
            enabled: true,
            onSeek: _noop,
          ),
        ),
      );
      final IconButton back = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.skip_previous),
          matching: find.byType(IconButton),
        ),
      );
      expect(back.onPressed, isNull);
    });

    testWidgets('step-forward is disabled at the last bar',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          const ReplayControls(
            cursor: 19,
            total: 20,
            enabled: true,
            onSeek: _noop,
          ),
        ),
      );
      final IconButton forward = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.skip_next),
          matching: find.byType(IconButton),
        ),
      );
      expect(forward.onPressed, isNull);
    });

    testWidgets('stepping reports the new cursor', (WidgetTester tester) async {
      int? seen;
      await tester.pumpWidget(
        _app(
          ReplayControls(
            cursor: 5,
            total: 20,
            enabled: true,
            onSeek: (int i) => seen = i,
          ),
        ),
      );
      await tester.tap(
        find.ancestor(
          of: find.byIcon(Icons.skip_next),
          matching: find.byType(IconButton),
        ),
      );
      expect(seen, 6);
    });

    testWidgets('a short series is called out rather than silently unplayable',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          const ReplayControls(
            cursor: 0,
            total: 3,
            enabled: true,
            onSeek: _noop,
          ),
        ),
      );
      expect(find.textContaining('Only 3 bars'), findsOneWidget);
    });

    testWidgets('nothing loaded states that plainly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          const ReplayControls(
            cursor: 0,
            total: 0,
            enabled: false,
            onSeek: _noop,
          ),
        ),
      );
      expect(find.textContaining('Nothing loaded yet'), findsOneWidget);
    });
  });

  group('the cursor only reveals a prefix of the series', () {
    // These are plain `test()`s, not widget tests, because they assert on a `ProviderContainer` and
    // never build a widget tree. `selectedBarsProvider` is overridden with a SYNCHRONOUS state rather
    // than driving a real notifier: the invariant under test — that a bar the trader has not stepped to
    // cannot reach the verdict — lives entirely in `visibleBarsProvider`, and stubbing the source keeps
    // the test independent of repository timing instead of merely tolerating it.
    ReplayBarsState readyState() => ReplayBarsState(
          status: ReplayBarsStatus.ready,
          series: PriceSeries(
            request: xauH1,
            bars: risingBars(count: 30),
            asOf: DateTime.now().toUtc(),
          ),
        );

    test('stepping exposes exactly one more bar at a time', () {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          selectedBarsProvider.overrideWithValue(readyState()),
          replaySetupProvider.overrideWith((Ref ref) => longSetup),
          replayCursorProvider.overrideWith((Ref ref) => 0),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(visibleBarsProvider), hasLength(1));

      container.read(replayCursorProvider.notifier).state = 4;
      expect(container.read(visibleBarsProvider), hasLength(5));

      // A cursor past the end clamps rather than throwing.
      container.read(replayCursorProvider.notifier).state = 999;
      expect(container.read(visibleBarsProvider), hasLength(30));

      container.read(replayCursorProvider.notifier).state = -5;
      expect(container.read(visibleBarsProvider), isEmpty);
    });

    test('a verdict can never rest on a bar the cursor has not reached', () {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          selectedBarsProvider.overrideWithValue(readyState()),
          replaySetupProvider.overrideWith((Ref ref) => longSetup),
        ],
      );
      addTearDown(container.dispose);

      int resolved = 0;
      for (int cursor = 0; cursor < 30; cursor++) {
        container.read(replayCursorProvider.notifier).state = cursor;
        final ReplayResult? result = container.read(replayVerdictProvider);
        if (result == null || !result.isResolved) continue;
        resolved++;
        expect(
          result.exitIndex,
          lessThanOrEqualTo(cursor),
          reason: 'a verdict at bar $cursor cited bar ${result.exitIndex}',
        );
      }
      // Without this, the loop would "pass" by never resolving anything.
      expect(resolved, greaterThan(0));
    });
  });

  group('the setup form derives scorable levels', () {
    testWidgets('both directions are offered before anything is chosen',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(ReplaySetupForm(cursorBar: _firstBar)));
      await _settle(tester);
      expect(find.text('LONG'), findsOneWidget);
      expect(find.text('SHORT'), findsOneWidget);
      // Nothing chosen yet, so no levels are claimed.
      expect(find.textContaining('ENTRY'), findsNothing);
    });

    testWidgets('choosing a direction publishes valid, readable levels',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(ReplaySetupForm(cursorBar: _firstBar)));
      await _settle(tester);
      await tester.tap(find.text('LONG'));
      await tester.pump();

      // The levels are spelled out rather than hidden behind the slider: these are the prices a real
      // order would use, so the trader has to be able to check them. `findsWidgets`, not
      // `findsOneWidget`: "STOP" also matches the "STOP WIDTH" slider label.
      expect(find.textContaining('Entry'), findsOneWidget);
      expect(find.textContaining('Stop'), findsWidgets);
      expect(find.textContaining('Target'), findsWidgets);
      expect(find.textContaining('of the account'), findsOneWidget);
      expect(find.textContaining('lots'), findsOneWidget);
    });

    testWidgets('a long puts the stop below the entry and the target above it',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(ReplaySetupForm(cursorBar: _firstBar)));
      await _settle(tester);
      await tester.tap(find.text('LONG'));
      await _settle(tester);

      // The rendered line is ENTRY, STOP, TARGET in that order, so the levels are not monotonic: a
      // long reads entry > stop and target > entry. Anything else is unscorable, and
      // `ReplaySetup.validationError` is what says so.
      final List<double> p = _levels(tester);
      expect(p, hasLength(3));
      expect(p[1], lessThan(p[0]), reason: 'a long stop sits below the entry');
      expect(p[2], greaterThan(p[0]), reason: 'a long target sits above the entry');
    });

    testWidgets('a short mirrors it: stop above the entry, target below',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(ReplaySetupForm(cursorBar: _firstBar)));
      await _settle(tester);
      await tester.tap(find.text('SHORT'));
      await _settle(tester);

      final List<double> p = _levels(tester);
      expect(p, hasLength(3));
      expect(p[1], greaterThan(p[0]), reason: 'a short stop sits above the entry');
      expect(p[2], lessThan(p[0]), reason: 'a short target sits below the entry');
    });

    testWidgets('"no target" clears the target rather than setting a 0R one',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(ReplaySetupForm(cursorBar: _firstBar)));
      await _settle(tester);
      await tester.tap(find.text('LONG'));
      await _settle(tester);
      expect(find.textContaining('TARGET'), findsWidgets);

      await tester.tap(find.text('No target'));
      await _settle(tester);

      // Both the chip and the derived Target row read "No target" — two widgets is correct here.
      expect(find.textContaining('No target'), findsNWidgets(2));
    });

    testWidgets('the stop width slider is offered and labelled',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(ReplaySetupForm(cursorBar: _firstBar)));
      await _settle(tester);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.textContaining('bar range'), findsOneWidget);
    });
  });

  group('the screen renders each read state distinctly', () {
    testWidgets('loading says so and claims nothing', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(const ReplayScreen(), repository: PendingBars()),
      );
      await tester.pump();
      expect(find.byType(ReplayStateView), findsOneWidget);
      expect(find.textContaining('Loading price history'), findsOneWidget);
    });

    testWidgets('no cached bars is not the same as a failure',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(const ReplayScreen(), state: cached(const <PriceBar>[])),
      );
      await _settle(tester);
      expect(find.textContaining('No bars cached'), findsOneWidget);
      expect(find.textContaining('Could not load'), findsNothing);
    });

    testWidgets('a too-short series explains the floor',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(const ReplayScreen(), state: cached(risingBars(count: 3))),
      );
      await _settle(tester);
      expect(find.textContaining('Too few bars'), findsOneWidget);
      expect(
        find.textContaining('${ReplayBarsNotifier.minimumBars}'),
        findsWidgets,
      );
    });

    testWidgets('a failure offers a retry and never says "no bars"',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(const ReplayScreen(), state: _failed),
      );
      await _settle(tester);
      // Matched on the failure MESSAGE, not the title: both begin "Could not load price history",
      // so a title-based finder matches two widgets and reads as a missing-widget failure.
      expect(find.textContaining('Check your connection'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('No bars cached'), findsNothing);
    });

    testWidgets('the not-configured case is named rather than looking offline',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(const ReplayScreen(), state: _notConfigured),
      );
      await _settle(tester);
      expect(find.textContaining('not available on this build'), findsOneWidget);
    });

    testWidgets('a ready series shows its provenance and the disclaimer',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          const ReplayScreen(),
          state: cached(risingBars()),
          setup: longSetup,
          cursor: 30,
        ),
      );
      await _settle(tester);
      expect(find.textContaining('Cached market data'), findsOneWidget);
      expect(find.byType(ReplayChart), findsOneWidget);
      expect(find.byType(ReplayControls), findsOneWidget);
      // The screen is a lazy ListView, so everything past the fold has to be scrolled to before a
      // finder can see it at all.
      await _scrollTo(tester, find.byType(ReplayVerdictCard));
      expect(find.byType(ReplayVerdictCard), findsOneWidget);
      await _scrollTo(tester, find.byType(ReplayScanCard));
      expect(find.byType(ReplayScanCard), findsOneWidget);
      // Compliance surface: a backtest carries the risk disclaimer on its own screen.
      await _scrollTo(tester, find.textContaining('Backtests are hypothetical'));
      expect(find.textContaining('Backtests are hypothetical'), findsOneWidget);
    });

    testWidgets('a stubbed series is labelled SYNTHETIC DEMO on the chart',
        (WidgetTester tester) async {
      // THE regression for this feature: a generated chart shown unlabelled is indistinguishable from
      // the market, and for a backtest that is the most misleading thing the product could ship.
      await tester.pumpWidget(
        _app(
          const ReplayScreen(),
          state: _synthetic,
          setup: longSetup,
          cursor: 30,
        ),
      );
      await _settle(tester);
      expect(find.text('SYNTHETIC DEMO'), findsOneWidget);
      expect(find.textContaining('not real market prices'), findsOneWidget);
    });
    testWidgets('a cached series carries no synthetic badge',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          const ReplayScreen(),
          state: cached(risingBars()),
          setup: longSetup,
          cursor: 30,
        ),
      );
      await _settle(tester);
      expect(find.text('SYNTHETIC DEMO'), findsNothing);
    });

    testWidgets('a failed refresh keeps the bars it already had',
        (WidgetTester tester) async {
      // The same rule `AiReviewNotifier` follows: a network failure must not destroy something the
      // trader can still read.
      await tester.pumpWidget(
        _app(
          const ReplayScreen(),
          state: _staleFailure,
          setup: longSetup,
          cursor: 30,
        ),
      );
      await _settle(tester);
      expect(find.textContaining('Check your connection'), findsOneWidget);
      expect(find.textContaining('Still showing the last bars'), findsOneWidget);
    });
  });

  group('layout', () {
    final Map<String, Size> devices = <String, Size>{
      'small': const Size(320, 640),
      'tall': const Size(390, 844),
      'large': const Size(430, 932),
    };

    devices.forEach((String name, Size size) {
      testWidgets('the screen does not overflow - $name',
          (WidgetTester tester) async {
        await _pumpAt(
          tester,
          _app(
            const ReplayScreen(),
            state: cached(risingBars()),
            setup: longSetup,
            cursor: 30,
          ),
          size: size,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(ReplayScreen), findsOneWidget);
      });

      testWidgets('the verdict card does not overflow - $name',
          (WidgetTester tester) async {
        await _pumpAt(
          tester,
          _app(
            const ReplayVerdictCard(
              setup: longSetup,
              result: ReplayResult(
                setup: longSetup,
                status: ReplayStatus.targetHit,
                fillIndex: 0,
                fillPrice: 100,
                exitIndex: 14,
                exitPrice: 106,
                barsHeld: 14,
                mfeR: 1.2,
                maeR: -0.6,
              ),
              visibleBars: 40,
            ),
            setup: longSetup,
          ),
          size: size,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('the transport does not overflow - $name',
          (WidgetTester tester) async {
        // Five 48px buttons exceed a 320px screen once padding is counted, which is why the bar is a
        // Wrap rather than a Row.
        await _pumpAt(
          tester,
          _app(
            const ReplayControls(
              cursor: 5,
              total: 40,
              enabled: true,
              onSeek: _noop,
            ),
          ),
          size: size,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('the scan card does not overflow - $name',
          (WidgetTester tester) async {
        await _pumpAt(
          tester,
          _app(
            ReplayScanCard(
              hasSetup: true,
              scan: ReplayScan(
                results: <ReplayResult>[
                  for (int i = 0; i < 12; i++)
                    ReplayResult(
                      setup: longSetup,
                      status: i.isEven
                          ? ReplayStatus.targetHit
                          : ReplayStatus.stopHit,
                      fillIndex: i,
                      exitIndex: i + 2,
                      exitPrice: i.isEven ? 106 : 97,
                    ),
                ],
                minimumTrades: 10,
              ),
            ),
            setup: longSetup,
          ),
          size: size,
        );
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('an empty series does not overflow the chart',
        (WidgetTester tester) async {
      await _pumpAt(
        tester,
        const MaterialApp(
          home: Scaffold(body: ReplayChart(bars: <PriceBar>[])),
        ),
      );
      expect(find.text('No bars to draw'), findsOneWidget);
    });

    testWidgets('the setup form does not overflow - small',
        (WidgetTester tester) async {
      await _pumpAt(
        tester,
        _app(ReplaySetupForm(cursorBar: _firstBar)),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// Scrolls [finder] into view, if it is not already built.
///
/// [ReplayScreen] is a `ListView`, so anything below the fold is not merely off-screen — it has not
/// been BUILT, and a finder cannot see it. Asserting on it without scrolling fails in a way that looks
/// like a missing widget rather than a missing scroll, which is exactly the kind of failure worth
/// encoding here rather than rediscovering.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(finder, 200, maxScrolls: 40);
  await tester.pump();
}

/// The three prices the form renders, in Entry, Stop, Target order.
///
/// Read from the rendered TEXT rather than from a provider, so the assertion covers what the trader
/// actually sees — including the case where the levels are ordered wrongly, which is precisely what
/// `ReplaySetup.validationError` exists to catch.
List<double> _levels(WidgetTester tester) {
  final List<Text> texts = tester.widgetList<Text>(find.byType(Text)).toList();
  double priceAfter(String label) {
    final int i = texts.indexWhere((Text t) => t.data == label);
    final String raw = texts[i + 1].data ?? '';
    return double.parse(RegExp(r'-?\d+\.?\d*').firstMatch(raw)!.group(0)!);
  }

  return <double>[
    priceAfter('Entry'),
    priceAfter('Stop'),
    priceAfter('Target'),
  ];
}