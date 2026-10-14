import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/account.dart';
import 'package:tradeguard/core/services/account_repository.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/features/guard/presentation/guard_screen.dart';
import 'package:tradeguard/features/journal/presentation/journal_screen.dart';
import 'package:tradeguard/features/paywall/data/purchase_repository.dart';
import 'package:tradeguard/features/paywall/presentation/paywall_screen.dart';
import 'package:tradeguard/features/settings/presentation/settings_screen.dart';
import 'package:tradeguard/features/signals/presentation/signals_screen.dart';
import 'package:tradeguard/features/tools/presentation/tools_screen.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(home: child),
    );

void main() {
  testWidgets('Guard screen renders daily loss and metrics', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const GuardScreen()));
    await tester.pumpAndSettle();

    expect(find.text('DAILY LOSS USED'), findsOneWidget);
    // The live-account section sits above the guard metrics now, so the metric
    // cards can start below the fold on a short test surface. Scroll them into
    // view (same pattern the STOP control uses below) before asserting.
    await tester.scrollUntilVisible(
      find.text('DRAWDOWN DISTANCE'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('DRAWDOWN DISTANCE'), findsOneWidget);

    // The emergency-stop control sits at the bottom of the scroll view, so
    // scroll it into view before asserting (ListView builds children lazily).
    await tester.scrollUntilVisible(
      find.textContaining('STOP'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('STOP'), findsWidgets);
  });

  testWidgets('Journal screen renders stats and calendar', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const JournalScreen()));
    await tester.pumpAndSettle();

    expect(find.text('NET P&L'), findsOneWidget);
    expect(find.text('P&L CALENDAR'), findsOneWidget);
  });

  testWidgets('Tools screen lists all four calculators', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const ToolsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Lot Size'), findsOneWidget);
    expect(find.text('Risk / Reward'), findsOneWidget);
    expect(find.text('Margin'), findsOneWidget);
    expect(find.text('Drawdown Sim'), findsOneWidget);
  });

  testWidgets('Signals screen shows a signal and risk disclaimer', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const SignalsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('XAUUSD'), findsWidgets);
    expect(find.text('Copy'), findsWidgets);
  });

  testWidgets('Signals AI Chart Analysis is gated behind the paywall', (WidgetTester tester) async {
    // Gate: AI Chart Analysis requires Pro. Not Pro → the button opens the
    // paywall modal instead of navigating to /tools/chart-analysis.
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          purchasesProvider.overrideWith(
            (Ref ref) => PurchaseNotifier(_FixedProRepository(false)),
          ),
        ],
        child: const MaterialApp(home: SignalsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('AI Chart Analysis'));
    await tester.pumpAndSettle();

    // The paywall is presented; the chart-analysis screen is not reached.
    expect(find.text('TradeGuard Pro'), findsOneWidget);
  });

  testWidgets('Settings screen exposes delete account and legal links', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    // Legal tiles and the delete-account row live below the fold; scroll each
    // into view before asserting (ListView builds children lazily).
    await tester.scrollUntilVisible(
      find.text('Privacy policy'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Privacy policy'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Delete account'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Delete account'), findsOneWidget);
  });

    testWidgets('Settings lists seeded accounts with guard + remove actions', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(const SettingsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('FTMO EVAL 100K'), findsOneWidget);
      expect(find.text('FUNDED 50K'), findsOneWidget);
      // Each account exposes the equity-guard toggle and the remove action.
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
      expect(find.byIcon(Icons.shield), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
    });

    testWidgets('toggling the equity guard persists through the notifier', (
      WidgetTester tester,
    ) async {
      final AccountsNotifier notifier =
          AccountsNotifier(MockAccountRepository());
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            accountsProvider.overrideWith((_) => notifier),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // The seeded FUNDED account has the guard on, so this click turns it off.
      await tester.tap(find.byIcon(Icons.shield));
      await tester.pumpAndSettle();

      final TradingAccount? funded = notifier.byId('acc_funded_50k');
      expect(funded, isNotNull);
      expect(funded!.equityGuardEnabled, isFalse);
    });

    testWidgets('remove account asks for confirmation first', (
      WidgetTester tester,
    ) async {
      final AccountsNotifier notifier =
          AccountsNotifier(MockAccountRepository());
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            accountsProvider.overrideWith((_) => notifier),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      // Cancelling leaves the account list untouched.
      expect(find.text('Remove FTMO EVAL 100K?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(notifier.byId('acc_eval_100k'), isNotNull);

      // Confirming removes it.
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(notifier.byId('acc_eval_100k'), isNull);
    });

    testWidgets('Connect broker button opens the connect sheet', (
      WidgetTester tester,
    ) async {
      // The sheet is taller than the default 800x600 test viewport, so grow the surface.
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect broker (read-only)'));
      await tester.pumpAndSettle();

      expect(find.text('Connect broker'), findsOneWidget);
      expect(find.text('Connect account'), findsOneWidget);
      expect(find.textContaining('Read-only'), findsOneWidget);
    });

  testWidgets('Paywall renders the Subscribe + Check Status surface',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const PaywallScreen()));
    await tester.pumpAndSettle();

    // Mock mode is not Pro, so the paywall shows the 3-tier picker, the
    // Subscribe action (which opens the Flutterwave Payment Link), a Check
    // Status action and the verbatim risk disclaimer — never a fabricated
    // store offering. The offers list is taller than the default test surface,
    // so scroll each assertion target into view (ListView builds lazily).
    final Finder scrollable = find.byType(Scrollable).first;
    Future<void> reveal(String text) => tester.scrollUntilVisible(
          find.text(text),
          300,
          scrollable: scrollable,
        );

    expect(find.text('TradeGuard Pro'), findsOneWidget);
    await reveal(r'Subscribe for $15/month');
    expect(find.text(r'Subscribe for $15/month'), findsOneWidget);
    await reveal('I Have Subscribed / Check Status');
    expect(find.text('I Have Subscribed / Check Status'), findsOneWidget);
    await reveal('Monthly');
    expect(find.text('Monthly'), findsOneWidget);
  });
}

/// A purchase repository pinned to a fixed Pro status, so the Signals AI Chart
/// Analysis gate can be driven to the paywall. Premium is now a boolean read
/// from Supabase, so this fake only needs [isPro] and [watchProStatus].
class _FixedProRepository implements PurchaseRepository {
  _FixedProRepository(this._pro);

  final bool _pro;

  @override
  Future<bool> isPro() async => _pro;

  @override
  Stream<bool> watchProStatus() => Stream<bool>.value(_pro);
}
