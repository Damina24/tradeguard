import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/core/theme/app_theme.dart';
import 'package:tradeguard/features/paywall/data/purchase_repository.dart';
import 'package:tradeguard/features/paywall/presentation/paywall_screen.dart';

/// A purchase repository driven entirely by its constructor, so every paywall
/// state (offers, Pro, loading, purchase failure) is reachable without a store.
class _FakePurchaseRepository implements PurchaseRepository {
  _FakePurchaseRepository({
    this.pro = false,
    this.packages = const <Object>[],
    this.pending = false,
    this.loadError,
    this.purchaseError,
  });

  final bool pro;
  final List<Object> packages;

  /// When true, `loadPackages` never completes, so the loading state can be seen.
  final bool pending;
  final Object? loadError;
  final Object? purchaseError;

  @override
  Future<bool> isPro() async => pro;

  @override
  Stream<bool> watchProStatus() => Stream<bool>.value(pro);

  @override
  Future<List<Object>> loadPackages() async {
    if (pending) return Completer<List<Object>>().future;
    final Object? e = loadError;
    if (e != null) throw e;
    return packages;
  }

  @override
  Future<void> purchase(Object package) async {
    final Object? e = purchaseError;
    if (e != null) throw e;
  }

  @override
  Future<void> restore() async {}
}

/// A store package with a human label and the store's own localized price.
Package _pkg(PackageType type, String title, String price) => Package(
      'id_${type.name}',
      type,
      StoreProduct('prod_${type.name}', 'desc', title, 9.99, price, 'USD'),
      const PresentedOfferingContext('default', null, null),
    );

Widget _app(PurchaseRepository repo) => ProviderScope(
      overrides: <Override>[
        purchasesProvider.overrideWith((Ref ref) => PurchaseNotifier(repo)),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const PaywallScreen()),
    );

/// Gives the paywall a phone-tall surface so the scrolling offers list builds
/// all of its children (the default 800x600 test viewport is too short).
void _usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('shows a loading indicator while offerings load',
      (WidgetTester tester) async {
    _usePhoneSurface(tester);
    await tester.pumpWidget(_app(_FakePurchaseRepository(pending: true)));
    // A single pump: the pending loadPackages never completes, and a spinner
    // animates forever, so pumpAndSettle could never return.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders store packages with title, price and Subscribe',
      (WidgetTester tester) async {
    _usePhoneSurface(tester);
    await tester.pumpWidget(
      _app(
        _FakePurchaseRepository(
          packages: <Object>[
            _pkg(PackageType.monthly, 'TradeGuard Pro Monthly', r'$9.99'),
            _pkg(PackageType.annual, 'TradeGuard Pro Annual', r'$99.99'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The plan label comes from the package type; the store title and price
    // come from the store product itself.
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Annual'), findsOneWidget);
    expect(find.text('TradeGuard Pro Monthly'), findsOneWidget);
    expect(find.text('TradeGuard Pro Annual'), findsOneWidget);
    expect(find.text(r'$9.99'), findsOneWidget);
    expect(find.text(r'$99.99'), findsOneWidget);
    // One Subscribe button per package.
    expect(find.widgetWithText(ElevatedButton, 'Subscribe'), findsNWidgets(2));
    // The paywall is a compliance surface, so the disclaimer is always shown.
    expect(find.textContaining('high-risk'), findsOneWidget);
  });

  testWidgets('Subscribe routes the chosen package to the notifier',
      (WidgetTester tester) async {
    _usePhoneSurface(tester);
    final _FakePurchaseRepository repo = _FakePurchaseRepository(
      packages: <Object>[
        _pkg(PackageType.monthly, 'TradeGuard Pro Monthly', r'$9.99'),
      ],
    );
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    // Tapping Subscribe calls purchase(package) on the repository; with no
    // error the notifier re-syncs and the offers remain (mock stays not-Pro).
    await tester.tap(find.widgetWithText(ElevatedButton, 'Subscribe'));
    await tester.pumpAndSettle();

    expect(find.text('Monthly'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Pro member sees a confirmation, not a purchase UI',
      (WidgetTester tester) async {
    _usePhoneSurface(tester);
    await tester.pumpWidget(
      _app(
        _FakePurchaseRepository(
          pro: true,
          packages: <Object>[_pkg(PackageType.monthly, 'Monthly', r'$9.99')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You are a Pro member'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    // No purchase surface for someone who already owns it.
    expect(find.widgetWithText(ElevatedButton, 'Subscribe'), findsNothing);
    expect(find.text('Restore Purchases'), findsNothing);
  });

  testWidgets('shows an empty-state message when no offerings are returned',
      (WidgetTester tester) async {
    _usePhoneSurface(tester);
    await tester.pumpWidget(_app(_FakePurchaseRepository()));
    await tester.pumpAndSettle();

    expect(find.textContaining('No subscription options'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Subscribe'), findsNothing);
    expect(find.text('Restore Purchases'), findsOneWidget);
  });

  testWidgets('surfaces a purchase failure as a trader-safe SnackBar',
      (WidgetTester tester) async {
    _usePhoneSurface(tester);
    await tester.pumpWidget(
      _app(
        _FakePurchaseRepository(
          packages: <Object>[_pkg(PackageType.monthly, 'Monthly', r'$9.99')],
          purchaseError: const PurchaseFailure('Could not reach the store.'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Subscribe'));
    await tester.pumpAndSettle();

    // The repository's trader-safe message is shown; no raw SDK text leaks.
    expect(find.text('Could not reach the store.'), findsOneWidget);
  });

  testWidgets('surfaces a load failure as a trader-safe SnackBar',
      (WidgetTester tester) async {
    _usePhoneSurface(tester);
    await tester.pumpWidget(
      _app(
        _FakePurchaseRepository(
          loadError: const PurchaseFailure('Store is unreachable.'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A failure to load offerings is reported as a SnackBar.
    expect(find.text('Store is unreachable.'), findsOneWidget);
  });
}
