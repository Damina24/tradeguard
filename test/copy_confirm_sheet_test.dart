import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/constants/app_strings.dart';
import 'package:tradeguard/core/models/account.dart';
import 'package:tradeguard/core/models/signal.dart';
import 'package:tradeguard/core/services/account_repository.dart';
import 'package:tradeguard/core/services/mock_data.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/core/theme/app_theme.dart';
import 'package:tradeguard/features/signals/presentation/copy_confirm_sheet.dart';

/// The S8 copy confirm sheet (task 3.4).
///
/// These tests assert on the numbers a trader makes decisions with — lots,
/// max loss, the cap refusal with its reported size — plus the two
/// compliance surfaces (PAPER MODE pill, verbatim disclaimer) and the
/// confirm → toast flow through a real modal route, so a regression in any
/// of them fails CI rather than reaching a trader.
void main() {
  /// The seeded XAUUSD call: entry 2345.50, stop 2338.00 (75 pips), tp1
  /// 2358.00 — the same fixture the parity table sizes.
  final Signal signal = MockData.signals().first;

  // The sheet is taller than the default 800x600 test viewport; give it a
  // tall surface so nothing overflows into a render error.
  Future<void> pumpSheet(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the sheet through a real `showModalBottomSheet`, exactly as the
  /// signals screen does, so `_confirm`'s pop + snackbar path is exercised.
  Future<void> pumpModal(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: const Color(0xFF121826),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  builder: (_) =>
                      CopyConfirmSheet(signal: MockData.signals().first),
                ),
                child: const Text('open sheet'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
  }

  Finder confirmButton() =>
      find.widgetWithText(ElevatedButton, 'Confirm Copy');
  group('CopyConfirmSheet', () {
    testWidgets('renders the S8 surface: summary, sizing, pill, disclaimer', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester, CopyConfirmSheet(signal: signal));

      // Header + paper-mode pill (the mode is disclosed, never implied).
      expect(find.text('Copy Signal'), findsOneWidget);
      expect(find.text('PAPER MODE'), findsOneWidget);

      // Signal summary: direction, stop width, R multiple, and the levels.
      expect(
        find.text('XAUUSD • BUY • 75.0 pips SL • 1:1.67'),
        findsOneWidget,
      );
      expect(
        find.text('Entry 2345.50 · SL 2338.00 · TP 2358.00'),
        findsOneWidget,
      );

      // Risk slider at the default 1%, inside the server's clamp band.
      expect(find.text('Risk: 1.00%'), findsOneWidget);
      final Slider slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 0.25);
      expect(slider.max, 5.0);

      // Pip value row (S8 explicitly lists it).
      expect(find.text('Pip value'), findsOneWidget);
      expect(find.textContaining('per pip'), findsOneWidget);

      // Per-account sizing: EVAL $103,450 -> 1.38 lots, FUNDED $51,820 ->
      // 0.69 lots, each with the loss at its own stop.
      expect(find.textContaining(r'$103,450.00 equity'), findsOneWidget);
      expect(find.text('1.38 lots'), findsOneWidget);
      expect(find.text(r'max loss $1,035.00'), findsOneWidget);
      expect(find.textContaining(r'$51,820.00 equity'), findsOneWidget);
      expect(find.text('0.69 lots'), findsOneWidget);
      expect(find.text(r'max loss $517.50'), findsOneWidget);

      // The preview/authorization split is stated, not just implemented.
      expect(find.textContaining('Preview only'), findsOneWidget);

      // Compliance: the disclaimer is AppStrings.riskDisclaimer verbatim —
      // a hand-written paraphrase is not allowed on this surface.
      expect(find.text(AppStrings.riskDisclaimer), findsOneWidget);
    });

    testWidgets('defaults the selection to the guard account, not all', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester, CopyConfirmSheet(signal: signal));

      expect(find.text('ACCOUNTS — 1 of 2 selected (max 10)'), findsOneWidget);
      final List<CheckboxListTile> tiles = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(tiles, hasLength(2));
      expect(tiles[0].value, isTrue); // FTMO EVAL 100K — the guard default
      expect(tiles[1].value, isFalse);

      // Confirm is live: the default selection sizes cleanly at 1%.
      expect(
        tester.widget<ElevatedButton>(confirmButton()).onPressed,
        isNotNull,
      );
    });

    testWidgets('recomputes on slider move and reports a cap refusal with its size', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester, CopyConfirmSheet(signal: signal));

      // 5% on $103,450 = 6.90 lots > the 5.00 cap: refused with the size,
      // and with only EVAL selected there is nothing placeable left.
      tester.widget<Slider>(find.byType(Slider)).onChanged!.call(5.0);
      await tester.pumpAndSettle();

      expect(find.text('6.90 lots'), findsOneWidget);
      expect(
        find.textContaining('6.90 lots is over the 5.00-lot cap'),
        findsOneWidget,
      );
      expect(
        find.textContaining('cannot be copied right now'),
        findsOneWidget,
      );
      expect(
        tester.widget<ElevatedButton>(confirmButton()).onPressed,
        isNull,
        reason: 'a refused-only selection must not be confirmable',
      );

      // FUNDED at 5% = 3.45 lots, inside the cap — selecting it makes the
      // request partially placeable again, so confirm returns.
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();

      expect(find.text('3.45 lots'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(confirmButton()).onPressed,
        isNotNull,
      );
      // The refused EVAL row keeps its reason — partial placeability never
      // hides why one account was dropped.
      expect(
        find.textContaining('6.90 lots is over the 5.00-lot cap'),
        findsOneWidget,
      );
    });

    testWidgets('confirm pops the sheet and toasts the paper simulation', (
      WidgetTester tester,
    ) async {
      await pumpModal(tester);
      expect(find.text('Copy Signal'), findsOneWidget);

      await tester.tap(find.text('Confirm Copy'));
      await tester.pumpAndSettle();

      // Sheet gone, toast honest about what did NOT happen.
      expect(find.text('Copy Signal'), findsNothing);
      expect(
        find.textContaining('Paper copy simulated: FTMO EVAL 100K 1.38 lots.'),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing sent to a broker'), findsOneWidget);
    });

    testWidgets('an accountless trader is told to connect, not shown zero lots', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            accountsProvider.overrideWith(
              (Ref ref) => AccountsNotifier(_EmptyAccounts()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(body: CopyConfirmSheet(signal: signal)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connect a broker account first.'), findsOneWidget);
      expect(find.text('Confirm Copy'), findsNothing);
    });
  });
}

/// Repository with no accounts, for the empty-sheet state.
class _EmptyAccounts implements AccountRepository {
  @override
  Future<List<TradingAccount>> fetchAccounts() async => <TradingAccount>[];

  @override
  Future<AccountSnapshot> fetchSnapshot(String accountId) async =>
      throw UnimplementedError();

  @override
  Future<TradingAccount> createAccount(TradingAccount account) async =>
      account;

  @override
  Future<void> deleteAccount(String accountId) async {}

  @override
  Future<void> setEquityGuardEnabled(String accountId, bool enabled) async {}

  @override
  Future<void> setCopyEnabled(String accountId, bool enabled) async {}
}


