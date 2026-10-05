import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/trade.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/core/services/trade_repository.dart';
import 'package:tradeguard/features/patterns/data/pattern_repository.dart';
import 'package:tradeguard/features/patterns/domain/pattern_row.dart';
import 'package:tradeguard/features/patterns/pattern_providers.dart';
import 'package:tradeguard/features/patterns/presentation/pattern_insights_screen.dart';

/// A `v_patterns` row.
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

/// A repository that never answers, so the loading state can be held open.
class _PendingRepository implements PatternRepository {
  @override
  Future<List<PatternRow>> fetchPatterns() =>
      Completer<List<PatternRow>>().future;
}

class _ToggleRepository implements PatternRepository {
  bool failing = true;

  @override
  Future<List<PatternRow>> fetchPatterns() async {
    if (failing) throw StateError('offline');
    return <PatternRow>[
      const PatternRow(
        userId: 'u1',
        symbol: 'XAUUSD',
        session: 'london',
        dayOfWeek: 1,
        hour: 8,
        pnl: -1420,
        trades: 24,
        winRate: 0.29,
      ),
    ];
  }
}

class FakePatternRepository implements PatternRepository {
  FakePatternRepository({this.rows = const <PatternRow>[], this.failure});

  final List<PatternRow> rows;
  final Object? failure;

  @override
  Future<List<PatternRow>> fetchPatterns() async {
    final Object? f = failure;
    if (f != null) throw f;
    return rows;
  }
}

/// A journal big enough to leave the insufficient-data state.
class _ManyTrades implements TradeRepository {
  @override
  Future<List<Trade>> fetchTrades({String? accountId, int limit = 200}) async =>
      List<Trade>.generate(
        60,
        (int i) => Trade(
          id: 't$i',
          accountId: 'a1',
          symbol: 'EURUSD',
          direction: TradeDirection.long,
          lots: 1,
          pnl: 10,
          closeTime: DateTime.utc(2026, 4, 1).add(Duration(hours: i)),
        ),
      );

  @override
  Future<void> updateGrade(String tradeId, String grade) async {}

  @override
  Future<void> updateNotes(String tradeId, String notes) async {}
}

Widget _app(
  Widget child, {
  List<PatternRow>? rows,
  Object? error,
  PatternRepository? repository,
}) {
  return ProviderScope(
    overrides: <Override>[
      patternStateProvider.overrideWith(
        (Ref ref) => PatternNotifier(
          repository ??
              FakePatternRepository(rows: rows ?? const <PatternRow>[], failure: error),
        ),
      ),
      tradesProvider.overrideWith((Ref ref) => TradesNotifier(_ManyTrades())),
    ],
    child: MaterialApp(home: child),
  );
}

void _useSurface(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Rows that produce both a populated pattern table and at least one leak.
List<PatternRow> populated() => <PatternRow>[
      row(symbol: 'XAUUSD', session: 'london', hour: 8, pnl: -1420, trades: 24, winRate: 0.29),
      row(symbol: 'EURUSD', session: 'newyork', hour: 14, pnl: 1120, trades: 22, winRate: 0.68),
      row(symbol: 'GBPUSD', session: 'asia', hour: 3, pnl: -310, trades: 12, winRate: 0.42),
    ];

/// Switches to the leaks tab.
Future<void> _goToLeaks(WidgetTester tester) async {
  await tester.tap(find.text('LEAKS'));
  await tester.pumpAndSettle();
}

void main() {
  group('states', () {
    testWidgets('loading shows a spinner and claims nothing', (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), repository: _PendingRepository()),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The key honesty check: no verdict text while the read is in flight.
      expect(find.textContaining('No leaks'), findsNothing);
      expect(find.textContaining('is net negative'), findsNothing);
    });

    testWidgets('no trades renders the empty state, not the error state',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), rows: const <PatternRow>[]),
      );
      await tester.pumpAndSettle();

      expect(find.text('No trades to find patterns in'), findsOneWidget);
      expect(find.text('Could not load your patterns'), findsNothing);
    });

    testWidgets('a thin sample renders insufficient data, NOT "no patterns"',
        (WidgetTester tester) async {
      _useSurface(tester);
      // Four trades: real data, below the reporting floor.
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), rows: <PatternRow>[
          row(symbol: 'A', pnl: -100, trades: 4),
        ],),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not enough data yet'), findsOneWidget);
      expect(find.text('No trades to find patterns in'), findsNothing);
    });

    testWidgets('the leaks tab says data is insufficient rather than leak-free',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), rows: <PatternRow>[
          row(symbol: 'A', pnl: -100, trades: 4),
        ],),
      );
      await tester.pumpAndSettle();
      await _goToLeaks(tester);

      expect(find.text('Not enough data to identify a leak'), findsOneWidget);
      // The critical distinction: this is NOT the same as "No leaks found".
      expect(find.text('No leaks found'), findsNothing);
    });

    testWidgets('a backend failure renders the error state with a retry',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), error: StateError('boom')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load your patterns'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('a clean journal says no leaks found, not an empty box',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), rows: <PatternRow>[
          row(symbol: 'GOOD', pnl: 2000, trades: 40),
          row(symbol: 'ALSO_GOOD', session: 'newyork', pnl: 900, trades: 25),
        ],),
      );
      await tester.pumpAndSettle();
      await _goToLeaks(tester);

      expect(find.text('No leaks found'), findsOneWidget);
      // Proves the sweep actually ran rather than silently failing.
      expect(find.textContaining('Reviewed'), findsOneWidget);
    });

    testWidgets('populated data renders the pattern table', (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), rows: populated()),
      );
      await tester.pumpAndSettle();

      expect(find.text('XAUUSD'), findsOneWidget);
      expect(find.text('EURUSD'), findsOneWidget);
      expect(find.text('GBPUSD'), findsOneWidget);
    });

    testWidgets('populated data renders leak cards with evidence',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), rows: populated()),
      );
      await tester.pumpAndSettle();
      await _goToLeaks(tester);

      expect(find.textContaining('is net negative'), findsWidgets);
      expect(find.textContaining('BASED ON'), findsWidgets);
      expect(find.textContaining('trade'), findsWidgets);
    });
  });

  group('data honesty in the UI', () {
    testWidgets('the sample size is shown on the screen', (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), rows: populated()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Based on 58 closed trades'), findsOneWidget);
    });

    testWidgets('a confidence word accompanies a leak', (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), rows: populated()),
      );
      await tester.pumpAndSettle();
      await _goToLeaks(tester);

      expect(find.text('Moderate sample'), findsWidgets);
    });

    testWidgets('the risk disclaimer is on the leaks tab', (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), rows: populated()),
      );
      await tester.pumpAndSettle();
      await _goToLeaks(tester);

      // It sits below the leak cards, so scroll it into view.
      await tester.scrollUntilVisible(
        find.textContaining('not advice'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('not advice'), findsOneWidget);
    });

    testWidgets('a thin slice is labelled rather than compared silently',
        (WidgetTester tester) async {
      _useSurface(tester, size: const Size(390, 1400));
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), rows: <PatternRow>[
          row(symbol: 'THIN', pnl: -90, trades: 2),
          row(symbol: 'BIG', session: 'newyork', hour: 9, pnl: 900, trades: 40),
        ],),
      );
      await tester.pumpAndSettle();

      expect(find.text('Too few trades to compare'), findsOneWidget);
    });

    testWidgets('sign and colour both convey the result, never colour alone',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), rows: populated()),
      );
      await tester.pumpAndSettle();

      // The signed number carries the meaning...
      expect(find.text('-\$1,420'), findsOneWidget);
      // ...and an arrow glyph with a semantic label reinforces it.
      expect(find.byIcon(Icons.trending_down), findsWidgets);
      expect(find.byIcon(Icons.trending_up), findsWidgets);
    });
  });

  group('interaction', () {
    testWidgets('switching dimension re-reads the same rows',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), rows: populated()),
      );
      await tester.pumpAndSettle();

      expect(find.text('XAUUSD'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'session'));
      await tester.pumpAndSettle();
      // Same data, different slice.
      expect(find.text('London'), findsOneWidget);
      expect(find.text('Newyork'), findsOneWidget);
    });

    testWidgets('changing the sort reorders the table', (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), rows: populated()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Net P&L'));
      await tester.pumpAndSettle();
      expect(find.text('EURUSD'), findsOneWidget);
    });

    testWidgets('the sort direction button toggles', (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const PatternInsightsScreen(), rows: populated()),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('retry re-reads the repository', (WidgetTester tester) async {
      _useSurface(tester);
      final _ToggleRepository repo = _ToggleRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            patternStateProvider.overrideWith((Ref ref) => PatternNotifier(repo)),
            tradesProvider.overrideWith((Ref ref) => TradesNotifier(_ManyTrades())),
          ],
          child: const MaterialApp(home: PatternInsightsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load your patterns'), findsOneWidget);

      repo.failing = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Could not load your patterns'), findsNothing);
      expect(find.text('XAUUSD'), findsOneWidget);
    });
  });

  layoutTests();
}

/// Layout verification across the sizes the app supports.
///
/// These are layout assertions, not snapshots: each screen is rendered at a
/// realistic width with deliberately hostile values and checked for RenderFlex
/// overflow, which is how a clipped symbol or a runaway row announces itself.
void layoutTests() {
  // Small phone, normal phone, large phone / phablet.
  const Map<String, Size> devices = <String, Size>{
    'narrow phone (320x640)': Size(320, 640),
    'normal phone (390x844)': Size(390, 844),
    'large phone (430x932)': Size(430, 932),
  };

  /// Values chosen to break layouts: a 300-character symbol, a seven-figure
  /// result, and a six-figure trade count.
  List<PatternRow> hostile() => <PatternRow>[
        row(
          symbol: 'VERYLONGSYMBOLNAMEWITHOUTANYBOUNDARY' * 6,
          pnl: -1234567.89,
          trades: 999999,
          winRate: 0.01,
        ),
        row(
          symbol: 'A',
          session: 'newyork',
          hour: 14,
          pnl: 9876543.21,
          trades: 123456,
          winRate: 0.99,
        ),
        row(
          symbol: 'B',
          session: 'asia',
          hour: 3,
          pnl: -0.01,
          trades: 5,
          winRate: 0.2,
        ),
      ];

  for (final MapEntry<String, Size> device in devices.entries) {
    group('layout — ${device.key}', () {
      testWidgets('the pattern tab does not overflow', (WidgetTester tester) async {
        _useSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(const PatternInsightsScreen(), rows: hostile()),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(PatternInsightsScreen), findsOneWidget);
      });

      testWidgets('the leaks tab does not overflow', (WidgetTester tester) async {
        _useSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(const PatternInsightsScreen(), rows: hostile()),
        );
        await tester.pumpAndSettle();
        await _goToLeaks(tester);

        expect(tester.takeException(), isNull);
      });

      testWidgets('many simultaneous leaks do not overflow',
          (WidgetTester tester) async {
        _useSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(const PatternInsightsScreen(), rows: <PatternRow>[
            row(symbol: 'A', session: 'london', hour: 8, dayOfWeek: 1, pnl: -900, trades: 30),
            row(symbol: 'B', session: 'newyork', hour: 14, dayOfWeek: 2, pnl: -800, trades: 25),
            row(symbol: 'C', session: 'asia', hour: 3, dayOfWeek: 5, pnl: -700, trades: 22),
            row(symbol: 'D', pnl: -600, trades: 60),
            row(symbol: 'E', pnl: -500, trades: 55),
          ],),
        );
        await tester.pumpAndSettle();
        await _goToLeaks(tester);

        expect(tester.takeException(), isNull);
      });

      testWidgets('a long leak title and recommendation do not overflow',
          (WidgetTester tester) async {
        _useSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(const PatternInsightsScreen(), rows: <PatternRow>[
            row(
              symbol: 'Q' * 250,
              pnl: -900,
              trades: 30,
            ),
          ],),
        );
        await tester.pumpAndSettle();
        await _goToLeaks(tester);

        expect(tester.takeException(), isNull);
      });

      testWidgets('the empty state does not overflow', (WidgetTester tester) async {
        _useSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(const PatternInsightsScreen(), rows: const <PatternRow>[]),
        );
        await tester.pumpAndSettle();
        await _goToLeaks(tester);

        expect(tester.takeException(), isNull);
      });

      testWidgets('the insufficient-data state does not overflow',
          (WidgetTester tester) async {
        _useSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(const PatternInsightsScreen(), rows: <PatternRow>[
            row(symbol: 'A', pnl: -10, trades: 2),
          ],),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('the error state does not overflow', (WidgetTester tester) async {
        _useSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(const PatternInsightsScreen(), error: StateError('boom')),
        );
        await tester.pumpAndSettle();
        await _goToLeaks(tester);

        expect(tester.takeException(), isNull);
      });
    });
  }
}
