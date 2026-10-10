import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/constants/app_config.dart';
import 'package:tradeguard/features/auth/presentation/auth_screen.dart';
import 'package:tradeguard/features/settings/presentation/settings_screen.dart';
// `url_launcher_platform_interface` is a transitive dependency of `url_launcher`
// (already resolved in the lockfile). It is imported here — not added as a new
// dependency — purely to install a fake UrlLauncherPlatform so `launchUrl` is
// recorded instead of opening a real browser. The lint that wants it declared
// directly is intentionally suppressed: adding a package dependency is out of
// scope for this fix, and the version in use is pinned by url_launcher itself.
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
/// The legal links must open the live GitHub Pages URLs in an external
/// browser, not show placeholder text.
///
/// The reported bug: Privacy Policy and Terms of Service showed "placeholder"
/// text. Two things caused it — the URLs in [AppConfig] were
/// `__PLACEHOLDER_DOMAIN__`, and the Settings tiles only printed the URL into a
/// SnackBar (a trader cannot tap raw text) instead of launching a browser.
///
/// These tests pin the live URLs and drive the real `launchUrl` path through a
/// recording [UrlLauncherPlatform], so a regression to a SnackBar or a
/// placeholder URL fails here.
void main() {
  late _RecordingLauncher launcher;
  late UrlLauncherPlatform original;

  setUp(() {
    original = UrlLauncherPlatform.instance;
    launcher = _RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() {
    // Restore whatever launcher was installed before this test ran.
    UrlLauncherPlatform.instance = original;
  });

  group('AppConfig legal URLs', () {
    test('privacy policy points at the live GitHub Pages site', () {
      expect(
        AppConfig.privacyUrl,
        'https://damina24.github.io/tradeguard-legal/',
      );
    });

    test('terms of service points at the dedicated terms page', () {
      expect(
        AppConfig.termsUrl,
        'https://damina24.github.io/tradeguard-legal/terms',
      );
    });

    test('terms URL is distinct from the privacy policy URL', () {
      expect(AppConfig.termsUrl, isNot(equals(AppConfig.privacyUrl)));
    });

    test('account deletion points at the live deletion page', () {
      expect(
        AppConfig.deleteAccountUrl,
        'https://damina24.github.io/tradeguard-legal/account-deletion',
      );
    });

    test('no URL still carries a placeholder domain', () {
      // The regression guard: every legal URL must resolve, so none may keep
      // the __PLACEHOLDER__ token that shipped to the field.
      for (final String url in <String>[
        AppConfig.privacyUrl,
        AppConfig.termsUrl,
        AppConfig.deleteAccountUrl,
      ]) {
        expect(url.contains('__PLACEHOLDER__'), isFalse, reason: url);
        expect(url.startsWith('https://'), isTrue, reason: url);
      }
    });
  });

  group('Settings legal tiles launch the browser', () {
    testWidgets('Privacy policy opens the live privacy URL', (
      WidgetTester tester,
    ) async {
      // Tall surface so the whole ListView can build; the tile is still below
      // the fold, so it is scrolled into view before the tap.
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Privacy policy'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Privacy policy'));
      await tester.pumpAndSettle();

      expect(launcher.launchedUrls, contains(AppConfig.privacyUrl));
      // Opened in an external browser, not an in-app WebView.
      expect(launcher.lastMode, PreferredLaunchMode.externalApplication);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Terms of service opens the live legal URL', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Terms of service'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Terms of service'));
      await tester.pumpAndSettle();

      expect(launcher.launchedUrls, contains(AppConfig.termsUrl));
      expect(tester.takeException(), isNull);
    });
  });

  group('Auth screen legal links launch the browser', () {
    testWidgets('Privacy policy link on the auth screen opens the live URL', (
      WidgetTester tester,
    ) async {
      // The legal links sit at the very bottom of the scrollable auth form.
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AuthScreen())),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Privacy policy'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Privacy policy'));
      await tester.pumpAndSettle();

      expect(launcher.launchedUrls, contains(AppConfig.privacyUrl));
      expect(tester.takeException(), isNull);
    });
  });
}

/// Records every URL handed to `launchUrl`, and the launch mode, so a test can
/// assert the exact external URL without a real browser.
class _RecordingLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = <String>[];
  PreferredLaunchMode? lastMode;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    lastMode = options.mode;
    return true;
  }

  @override
  LinkDelegate? get linkDelegate => null;
}
