import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/core/theme/app_theme.dart';
import 'package:tradeguard/features/paywall/data/purchase_repository.dart';
import 'package:tradeguard/features/paywall/presentation/paywall_screen.dart';
// `url_launcher_platform_interface` is a transitive dependency of `url_launcher`
// (already resolved in the lockfile). It is imported here — not added as a new
// dependency — purely to install a fake UrlLauncherPlatform so the Subscribe
// button's `launchUrl` is recorded instead of opening a real browser. The lint
// that wants it declared directly is intentionally suppressed (same pattern as
// `legal_links_test.dart`).
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// A purchase repository driven entirely by its constructor, so every paywall
/// state (offers, Pro, loading) is reachable without a backend. Premium is now
/// a single boolean, so this only controls [isPro] and whether the read is
/// still pending.
class _FakePurchaseRepository implements PurchaseRepository {
  _FakePurchaseRepository({
    this.pro = false,
    this.pending = false,
  });

  final bool pro;

  /// When true, `isPro` never completes, so the loading state can be seen.
  final bool pending;

  @override
  Future<bool> isPro() async {
    if (pending) return Completer<bool>().future;
    return pro;
  }

  @override
  Stream<bool> watchProStatus() => Stream<bool>.value(pro);
}

/// Records every URL handed to `launchUrl` so a test can assert the exact
/// Flutterwave Payment Link without a real browser.
class _RecordingLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = <String>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return true;
  }

  @override
  LinkDelegate? get linkDelegate => null;
}

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
  late _RecordingLauncher launcher;
  late UrlLauncherPlatform original;

  setUp(() {
    original = UrlLauncherPlatform.instance;
    launcher = _RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = original;
  });

  testWidgets('shows a loading indicator while the premium flag is read',
      (WidgetTester tester) async {
    _usePhoneSurface(tester);
    await tester.pumpWidget(_app(_FakePurchaseRepository(pending: true)));
    // A single pump: the pending isPro never completes, and a spinner animates
    // forever, so pumpAndSettle could never return.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders the Subscribe + Check Status actions and the disclaimer',
      (WidgetTester tester) async {
    _usePhoneSurface(tester);
    await tester.pumpWidget(_app(_FakePurchaseRepository()));
    await tester.pumpAndSettle();

    expect(find.text(r'Subscribe for $15/month'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text(r'$15/month'), findsOneWidget);
    expect(find.text('Quarterly'), findsOneWidget);
    expect(find.text(r'$40/3 months (Save 11%)'), findsOneWidget);
    expect(find.text('Yearly'), findsOneWidget);
    expect(find.text(r'$150/year (Save 16%)'), findsOneWidget);
    expect(find.text('I Have Subscribed / Check Status'), findsOneWidget);
    // The paywall is a compliance surface, so the disclaimer is always shown.
    expect(find.textContaining('high-risk'), findsOneWidget);
  });

  testWidgets('Subscribe opens the Flutterwave Payment Link in the browser',
      (WidgetTester tester) async {
    _usePhoneSurface(tester);
    await tester.pumpWidget(_app(_FakePurchaseRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(r'Subscribe for $15/month'));
    await tester.pumpAndSettle();

    // The monthly Flutterwave Payment Link is launched externally by default.
    expect(
      launcher.launchedUrls,
      contains('https://flutterwave.com/pay/MONTHLY_LINK_HERE'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Selecting Quarterly opens the quarterly Flutterwave link',
      (WidgetTester tester) async {
    _usePhoneSurface(tester);
    await tester.pumpWidget(_app(_FakePurchaseRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Quarterly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'Subscribe for $40/3 months'));
    await tester.pumpAndSettle();

    expect(
      launcher.launchedUrls,
      contains('https://flutterwave.com/pay/QUARTERLY_LINK_HERE'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Pro member sees a confirmation, not a purchase UI',
      (WidgetTester tester) async {
    _usePhoneSurface(tester);
    await tester.pumpWidget(_app(_FakePurchaseRepository(pro: true)));
    await tester.pumpAndSettle();

    expect(find.text('You are a Pro member'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    // No purchase surface for someone who already owns it.
    expect(find.text(r'Subscribe for $15/month'), findsNothing);
    expect(find.text('I Have Subscribed / Check Status'), findsNothing);
  });

  testWidgets(
      'Check Status on a not-yet-premium trader reports it did not find it',
      (WidgetTester tester) async {
    _usePhoneSurface(tester);
    await tester.pumpWidget(_app(_FakePurchaseRepository(pro: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('I Have Subscribed / Check Status'));
    await tester.pumpAndSettle();

    // Not premium yet: the trader is told the payment has not been seen, and
    // the paywall stays open.
    expect(
      find.textContaining('could not find your subscription'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
