import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/core/theme/app_theme.dart';
import 'package:tradeguard/features/paywall/data/purchase_repository.dart';
import 'package:tradeguard/features/paywall/presentation/paywall_screen.dart';

/// The paywall's behaviour with no store products yet, which is the state a
/// signed-in FREE user on a fresh RevenueCat project sees: a valid platform key
/// but no configured offering.
///
/// This is the exact production path that used to be unreachable in testing,
/// because `Services.purchases` was `MockPurchaseRepository()` in mock mode. It
/// must render its empty state, never throw and never invent a price.
void main() {
  /// The live RevenueCat repository with no platform key — which is what an
  /// unconfigured build degrades to. `_isConfigured` stays false, so no store
  /// SDK call is made and every method answers offline.
  Future<void> pumpEmptyPaywall(WidgetTester tester) async {
    // Tall surface so the whole ListView (hero, offers, restore, disclaimer)
    // builds rather than being lazily skipped.
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          purchasesProvider.overrideWith(
            (Ref ref) => PurchaseNotifier(RevenueCatPurchaseRepository()),
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const PaywallScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the live repository with no store key is not configured', (
    WidgetTester tester,
  ) async {
    // No key means RevenueCatConfig.isConfigured is false, so the repository
    // never touches the store SDK and answers offline.
    final PurchaseRepository repo = RevenueCatPurchaseRepository();
    expect(await repo.isPro(), isFalse);
    expect(await repo.loadPackages(), isEmpty);
  });

  testWidgets('the live repository refuses a purchase with trader-safe copy', (
    WidgetTester tester,
  ) async {
    final PurchaseRepository repo = RevenueCatPurchaseRepository();
    await expectLater(
      repo.purchase(Object()),
      throwsA(
        isA<PurchaseFailure>().having(
          (PurchaseFailure e) => e.message,
          'message',
          contains('not configured'),
        ),
      ),
    );
  });

  testWidgets('watchProStatus answers false once and ends, never throws', (
    WidgetTester tester,
  ) async {
    final PurchaseRepository repo = RevenueCatPurchaseRepository();
    // An unconfigured build is never Pro. A single `false` then done, so a
    // listener that awaits completion cannot hang.
    expect(await repo.watchProStatus().toList(), <bool>[false]);
  });

  testWidgets('the paywall renders its empty-offers state without crashing', (
    WidgetTester tester,
  ) async {
    await pumpEmptyPaywall(tester);

    // The surface itself.
    expect(find.text('TradeGuard Pro'), findsOneWidget);

    // The empty state is explained, not shown as a bare blank list.
    expect(find.textContaining('No subscription options'), findsOneWidget);

    // No Subscribe button, because there is nothing to subscribe to.
    expect(find.widgetWithText(ElevatedButton, 'Subscribe'), findsNothing);

    // Restore Purchases still works with no offerings — a trader who bought
    // elsewhere must still be able to claim it.
    expect(find.text('Restore Purchases'), findsOneWidget);

    // A paywall is a compliance surface, so the disclaimer is always present.
    expect(find.textContaining('high-risk'), findsOneWidget);

    // The Equity Guard / Kill Switch / STOP copy promises these stay free.
    expect(find.textContaining('stay free for every trader'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Restore on an unconfigured build surfaces a safe message', (
    WidgetTester tester,
  ) async {
    await pumpEmptyPaywall(tester);

    await tester.tap(find.text('Restore Purchases'));
    await tester.pumpAndSettle();

    // Trader-safe wording from PurchaseFailure, never a raw SDK string.
    expect(find.text('Purchases are not configured for this build.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
