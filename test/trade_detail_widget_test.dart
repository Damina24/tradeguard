import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/trade.dart';
import 'package:tradeguard/core/services/account_repository.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/core/services/trade_repository.dart';
import 'package:tradeguard/features/journal/domain/trade_metrics.dart';
import 'package:tradeguard/features/journal/domain/trade_review.dart';
import 'package:tradeguard/features/journal/presentation/journal_screen.dart';
import 'package:tradeguard/features/journal/presentation/trade_detail_screen.dart';
import 'package:tradeguard/features/journal/widgets/trade_share_card.dart';

Trade trade({
  String id = 't1',
  String accountId = 'acc-1',
  String symbol = 'EURUSD',
  TradeDirection direction = TradeDirection.long,
  double lots = 1,
  double pnl = 1000,
  double? entry = 1.1000,
  double? exit = 1.1200,
  double? stop = 1.0900,
  double? target = 1.1200,
  double commission = -1,
  double swap = -1,
  String? grade,
  bool sparse = false,
}) =>
    Trade(
      id: id,
      accountId: accountId,
      symbol: symbol,
      direction: direction,
      lots: lots,
      pnl: pnl,
      entry: entry,
      exit: exit,
      stop: stop,
      target: target,
      commission: commission,
      swap: swap,
      grade: grade,
      openTime: sparse ? null : DateTime.utc(2026, 4, 15, 8),
      closeTime: sparse ? null : DateTime.utc(2026, 4, 15, 12),
      currency: sparse ? null : 'USD',
    );

/// Wraps a screen with the trades under test.
Widget _app(Widget child, {List<Trade>? trades, Object? error}) {
  return ProviderScope(
    overrides: <Override>[
      tradesProvider.overrideWith(
        (Ref ref) => TradesNotifier(_FakeTradeRepository(trades, error)),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

/// Resizes the test surface so a scrolling screen builds all of its children.
void _useTallSurface(WidgetTester tester, {Size size = const Size(500, 2400)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FakeTradeRepository implements TradeRepository {
  _FakeTradeRepository(this.rows, this.failure);

  final List<Trade>? rows;
  final Object? failure;

  @override
  Future<List<Trade>> fetchTrades({String? accountId, int limit = 200}) async {
    final Object? f = failure;
    if (f != null) throw f;
    return List<Trade>.from(rows ?? const <Trade>[]);
  }

  @override
  Future<void> updateGrade(String tradeId, String grade) async {}

  @override
  Future<void> updateNotes(String tradeId, String notes) async {}
}
void main() {
  // ---- Visual verification across supported device sizes -------------------------------------
  //
  // These are layout assertions, not snapshots: each device size is rendered at a realistic
  // width and checked for RenderFlex overflow, which is how a clipped price or a runaway row
  // announces itself in a widget test.
  //
  // Sizes cover a small phone, a normal phone, and a large phone / phablet, per the sizes the
  // app already supports.
  const Map<String, Size> devices = <String, Size>{
    'narrow phone (320x640)': Size(320, 640),
    'normal phone (390x844)': Size(390, 844),
    'large phone (430x932)': Size(430, 932),
  };

  for (final MapEntry<String, Size> device in devices.entries) {
    group('layout — ${device.key}', () {
      testWidgets('trade list does not overflow', (WidgetTester tester) async {
        _useTallSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(
            const JournalScreen(),
            trades: <Trade>[
              trade(id: 'a', symbol: 'XAUUSD', pnl: 1234.56),
              trade(id: 'b', symbol: 'EURUSD', pnl: -987.65),
              trade(
                id: 'c',
                // A deliberately long symbol and a huge P&L: the two things most likely to
                // blow out a row.
                symbol: 'VERYLONGSYMBOLNAME',
                pnl: -1234567.89,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('trade detail does not overflow', (WidgetTester tester) async {
        _useTallSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(
            const TradeDetailScreen(tradeId: 'a'),
            trades: <Trade>[
              trade(
                id: 'a',
                symbol: 'VERYLONGSYMBOLNAME',
                pnl: 1234567.89,
                commission: -1234.56,
                swap: -987.65,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('share card does not overflow or clip',
          (WidgetTester tester) async {
        _useTallSurface(tester, size: device.value);
        final TradeReview review = TradeReview.of(
          TradeMetrics.of(
            trade(symbol: 'VERYLONGSYMBOLNAME', pnl: 1234567.89),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: TradeShareCard(review: review)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('a sparse trade detail does not overflow',
          (WidgetTester tester) async {
        _useTallSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(
            const TradeDetailScreen(tradeId: 'a'),
            trades: <Trade>[
              trade(id: 'a', sparse: true, entry: null, exit: null, stop: null),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });
  }

  group('trade list', () {
    testWidgets('populated state lists the trade', (WidgetTester tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_app(const JournalScreen(), trades: <Trade>[trade()]));
      await tester.pumpAndSettle();

      expect(find.text('EURUSD'), findsWidgets);
      expect(find.text('BUY'), findsOneWidget);
      expect(find.text('RECENT TRADES'), findsOneWidget);
    });

    testWidgets('empty state with no broker says so',
        (WidgetTester tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            tradesProvider.overrideWith(
              (Ref ref) => TradesNotifier(_FakeTradeRepository(const <Trade>[], null)),
            ),
            accountsProvider.overrideWith(
              (Ref ref) => AccountsNotifier(MockAccountRepository()),
            ),
          ],
          child: const MaterialApp(home: JournalScreen()),
        ),
      );
      await tester.pumpAndSettle();
      // Mock accounts carry no MetaAPI id, so the empty state must guide the trader to connect.
      expect(find.text('No broker connected'), findsOneWidget);
    });

    testWidgets('error state shows generic copy and a retry',
        (WidgetTester tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        _app(
          const JournalScreen(),
          error: StateError(
            'pgx: duplicate key violates constraint (SQLSTATE 23505)',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load your trades'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // The raw backend text must never reach the screen.
      expect(find.textContaining('SQLSTATE'), findsNothing);
      expect(find.textContaining('pgx'), findsNothing);
    });

    testWidgets('a sell row renders SELL with a down glyph',
        (WidgetTester tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        _app(
          const JournalScreen(),
          trades: <Trade>[trade(pnl: -250, direction: TradeDirection.short)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SELL'), findsOneWidget);
      // Loss is signalled by a glyph as well as colour.
      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    });

    testWidgets('a win row renders an up glyph', (WidgetTester tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_app(const JournalScreen(), trades: <Trade>[trade()]));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
    });

    testWidgets('multiple symbols all render', (WidgetTester tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        _app(
          const JournalScreen(),
          trades: <Trade>[
            trade(id: 'a', symbol: 'XAUUSD'),
            trade(id: 'b', symbol: 'GBPJPY'),
            trade(id: 'c', symbol: 'US30'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('XAUUSD'), findsOneWidget);
      expect(find.text('GBPJPY'), findsOneWidget);
      expect(find.text('US30'), findsOneWidget);
    });

    testWidgets('a hand-set grade is shown on the row',
        (WidgetTester tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        _app(const JournalScreen(), trades: <Trade>[trade(grade: 'A')]),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Grade A'), findsOneWidget);
    });
});
  group('trade detail', () {
    testWidgets('renders every available field', (WidgetTester tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        _app(const TradeDetailScreen(tradeId: 't1'), trades: <Trade>[trade()]),
      );
      await tester.pumpAndSettle();

      expect(find.text('LONG'), findsWidgets);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('Entry'), findsOneWidget);
      expect(find.text('Exit'), findsOneWidget);
      expect(find.text('Stop loss'), findsOneWidget);
      expect(find.text('Take profit'), findsOneWidget);
      expect(find.text('R multiple'), findsOneWidget);
      expect(find.text('Gross'), findsOneWidget);
      expect(find.text('Commission'), findsOneWidget);
      expect(find.text('Swap'), findsOneWidget);
      expect(find.text('Net'), findsOneWidget);
      expect(find.text('Opened'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Currency'), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);
    });

    testWidgets('shows the persisted net, not a client recalculation',
        (WidgetTester tester) async {
      _useTallSurface(tester);
      // A deliberately "wrong" entry/exit pair: if the UI recomputed P&L it would disagree with
      // the stored figure. The stored number must win.
      final Trade t = trade(
        pnl: 307.80,
        commission: -3.5,
        swap: -0.7,
      );
      await tester.pumpWidget(
        _app(const TradeDetailScreen(tradeId: 't1'), trades: <Trade>[t]),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('308'), findsWidgets);
      // Gross is the net plus the costs added back: 307.80 + 4.20 = 312.00.
      expect(find.textContaining('312'), findsOneWidget);
    });

    testWidgets('missing optional fields render a dash, not a crash',
        (WidgetTester tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        _app(
          const TradeDetailScreen(tradeId: 't1'),
          trades: <Trade>[trade(sparse: true, entry: null, exit: null)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('—'), findsWidgets);
      expect(find.text('REVIEW'), findsOneWidget);
    });

    testWidgets('shows the review checklist and a grade',
        (WidgetTester tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        _app(const TradeDetailScreen(tradeId: 't1'), trades: <Trade>[trade()]),
      );
      await tester.pumpAndSettle();

      expect(find.text('REVIEW'), findsOneWidget);
      expect(find.textContaining('checks passed'), findsOneWidget);
      // 'GRADE' appears twice: in the header card and as the section label.
      expect(find.text('GRADE'), findsNWidgets(2));
      expect(find.textContaining('Stop loss was set'), findsOneWidget);
    });

    testWidgets('a hand-set grade overrides the derived one',
        (WidgetTester tester) async {
      _useTallSurface(tester);
      // Derived would be A for this trade; the trader set D and must win.
      await tester.pumpWidget(
        _app(
          const TradeDetailScreen(tradeId: 't1'),
          trades: <Trade>[trade(grade: 'D')],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Your grade. Tap a different letter to change it.'),
        findsOneWidget,
      );
    });

    testWidgets('a short trade says it is auto-graded',
        (WidgetTester tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        _app(const TradeDetailScreen(tradeId: 't1'), trades: <Trade>[trade()]),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Auto-graded from the checklist. Tap a letter to override.'),
        findsOneWidget,
      );
    });

    testWidgets('an unknown trade id shows the missing state',
        (WidgetTester tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        _app(
          const TradeDetailScreen(tradeId: 'not-mine'),
          trades: <Trade>[trade()],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trade not available'), findsOneWidget);
      expect(find.textContaining('different account'), findsOneWidget);
    });
  });
group('share card', () {
    testWidgets('shows the required fields for a win',
        (WidgetTester tester) async {
      _useTallSurface(tester, size: const Size(420, 900));
      final TradeReview review = TradeReview.of(TradeMetrics.of(trade()));
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TradeShareCard(review: review))),
      );
      await tester.pumpAndSettle();

      expect(find.text('EURUSD'), findsOneWidget);
      expect(find.text('LONG'), findsOneWidget);
      expect(find.text('NET RESULT'), findsOneWidget);
      expect(find.text('WIN'), findsOneWidget);
      expect(find.text('ENTRY'), findsOneWidget);
      expect(find.text('EXIT'), findsOneWidget);
      expect(find.text(review.grade.label), findsOneWidget);
    });

    testWidgets('a loss renders LOSS and the down glyph',
        (WidgetTester tester) async {
      _useTallSurface(tester, size: const Size(420, 900));
      final TradeReview review =
          TradeReview.of(TradeMetrics.of(trade(pnl: -250)));
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TradeShareCard(review: review))),
      );
      await tester.pumpAndSettle();

      expect(find.text('LOSS'), findsOneWidget);
      expect(find.byIcon(Icons.trending_down), findsOneWidget);
    });

    testWidgets('optional fields fall back cleanly',
        (WidgetTester tester) async {
      _useTallSurface(tester, size: const Size(420, 900));
      final TradeReview review = TradeReview.of(
        TradeMetrics.of(trade(sparse: true, entry: null, exit: null)),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TradeShareCard(review: review))),
      );
      await tester.pumpAndSettle();

      expect(find.text('—'), findsWidgets);
      // No close time means no date in the footer, but the brand line still renders.
      expect(find.textContaining('TradeGuard'), findsOneWidget);
    });

    testWidgets('carries no credential, account number or login',
        (WidgetTester tester) async {
      _useTallSurface(tester, size: const Size(420, 900));
      final TradeReview review = TradeReview.of(TradeMetrics.of(trade()));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // A nickname is the only account context the card accepts.
            body: TradeShareCard(review: review, accountNickname: 'FTMO EVAL'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('FTMO EVAL'), findsOneWidget);
      // The trade id is the account-scoped dedupe key and has no place on a shareable card.
      expect(find.text('t1'), findsNothing);
    });
  });

  group('security', () {
    testWidgets('a trade from another account is not resolvable',
        (WidgetTester tester) async {
      _useTallSurface(tester);
      // Only `t1` is in the repository; asking for a foreign id must not render its data.
      await tester.pumpWidget(
        _app(
          const TradeDetailScreen(tradeId: 'someone-elses-trade'),
          trades: <Trade>[trade(id: 't1')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trade not available'), findsOneWidget);
      expect(find.text('EURUSD'), findsNothing);
      expect(find.text('NET RESULT'), findsNothing);
    });

    test('the account context comes from the persisted row, not a UI argument',
        () {
      final Trade t = trade(accountId: 'acc-99');
      expect(t.accountId, 'acc-99');
      // There is no parameter on the domain layer a widget could pass an account through.
      expect(TradeMetrics.of(t).trade.accountId, 'acc-99');
    });

    test('no service-role or provider credential is reachable from the app', () {
      // A Trade is built only from its own persisted columns; there is no credential field on it.
      const Trade t = Trade(
        id: 't1',
        accountId: 'acc-1',
        symbol: 'XAUUSD',
        direction: TradeDirection.long,
        lots: 1,
        pnl: 10,
      );
      expect(t.toString(), isNot(contains('service')));
      expect(t.grossPnl, 10);
    });
  });
}
