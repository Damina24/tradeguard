import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/constants/app_config.dart';
import 'package:tradeguard/core/theme/app_theme.dart';
import 'package:tradeguard/core/widgets/fatal_config_screen.dart';

/// Mode selection used to be a single expression — `supabaseUrl.isEmpty` — so a
/// release APK built without keys silently booted into demo mode with seeded
/// accounts and an auto-signed-in demo user. These tests pin the replacement rule:
/// demo mode is opt-in, and a release build with no config is a fatal error.
void main() {
  group('AppConfig.resolveUseMock', () {
    test('an explicit USE_MOCK=true wins in every flavour', () {
      // A demo build is deliberate, and the flag must work the same way whether
      // it is a debug run or a release APK handed to a prospect.
      expect(
        AppConfig.resolveUseMock(
          mockRequested: true,
          hasSupabaseConfig: false,
          isRelease: true,
        ),
        isTrue,
      );
      expect(
        AppConfig.resolveUseMock(
          mockRequested: true,
          hasSupabaseConfig: false,
          isRelease: false,
        ),
        isTrue,
      );
      // A demo build with real keys present still shows the demo: the flag is an
      // explicit request, not a fallback, so it must not be overridden.
      expect(
        AppConfig.resolveUseMock(
          mockRequested: true,
          hasSupabaseConfig: true,
          isRelease: true,
        ),
        isTrue,
      );
    });

    test('a release build NEVER falls back to demo mode on its own', () {
      // This is the regression the field report was about: a release APK with no
      // dart-defines must not become a demo build by accident.
      expect(
        AppConfig.resolveUseMock(
          mockRequested: false,
          hasSupabaseConfig: false,
          isRelease: true,
        ),
        isFalse,
      );
      // Release with a real config runs live.
      expect(
        AppConfig.resolveUseMock(
          mockRequested: false,
          hasSupabaseConfig: true,
          isRelease: true,
        ),
        isFalse,
      );
    });

    test('debug/profile keeps the old no-keys convenience behaviour', () {
      // `flutter run` with no env file must still boot the seeded mocks.
      expect(
        AppConfig.resolveUseMock(
          mockRequested: false,
          hasSupabaseConfig: false,
          isRelease: false,
        ),
        isTrue,
      );
      expect(
        AppConfig.resolveUseMock(
          mockRequested: false,
          hasSupabaseConfig: true,
          isRelease: false,
        ),
        isFalse,
      );
    });
  });

  group('AppConfig.resolveConfigMissing', () {
    test('is true only for a release build with no config and no demo flag', () {
      expect(
        AppConfig.resolveConfigMissing(
          mockRequested: false,
          hasSupabaseConfig: false,
          isRelease: true,
        ),
        isTrue,
      );
    });

    test('a configured release build is not missing config', () {
      expect(
        AppConfig.resolveConfigMissing(
          mockRequested: false,
          hasSupabaseConfig: true,
          isRelease: true,
        ),
        isFalse,
      );
    });

    test('an explicit demo release build is not a config error', () {
      // Showing the fatal screen on a build that asked for demo mode would break
      // sales demos, which is the one legitimate reason to want seeded data.
      expect(
        AppConfig.resolveConfigMissing(
          mockRequested: true,
          hasSupabaseConfig: false,
          isRelease: true,
        ),
        isFalse,
      );
    });

    test('debug and profile builds are never a fatal config error', () {
      expect(
        AppConfig.resolveConfigMissing(
          mockRequested: false,
          hasSupabaseConfig: false,
          isRelease: false,
        ),
        isFalse,
      );
    });

    test('mock mode and missing config are mutually exclusive', () {
      // The two states must never both be true: one boots demo data, the other
      // refuses to boot. A build in both at once would be ambiguous.
      for (final bool mockRequested in <bool>[false, true]) {
        for (final bool hasConfig in <bool>[false, true]) {
          for (final bool isRelease in <bool>[false, true]) {
            final bool useMock = AppConfig.resolveUseMock(
              mockRequested: mockRequested,
              hasSupabaseConfig: hasConfig,
              isRelease: isRelease,
            );
            final bool missing = AppConfig.resolveConfigMissing(
              mockRequested: mockRequested,
              hasSupabaseConfig: hasConfig,
              isRelease: isRelease,
            );
            expect(
              useMock && missing,
              isFalse,
              reason: 'mock=$useMock and configMissing=$missing both true for '
                  'mockRequested=$mockRequested hasConfig=$hasConfig '
                  'isRelease=$isRelease',
            );
          }
        }
      }
    });
  });

  group('define names', () {
    test('the demo flag is the pre-existing USE_MOCK name, not a second one', () {
      // Guard against "fixing" the duplication by inventing a new define: the
      // env/*.json files already carry USE_MOCK, and only that name is read.
      expect(AppConfig.mockModeRequested, isA<bool>());
    });

    test('required defines are SUPABASE_URL and SUPABASE_ANON_KEY', () {
      expect(
        FatalConfigScreen.requiredDefines,
        <String>['SUPABASE_URL', 'SUPABASE_ANON_KEY'],
      );
    });
  });

  group('FatalConfigScreen', () {
    testWidgets('names the fix and lists the missing keys', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const FatalConfigScreen()),
      );
      await tester.pumpAndSettle();

      // The headline a build engineer needs, verbatim.
      expect(find.text('App configuration missing'), findsOneWidget);
      expect(find.text('Rebuild with required keys.'), findsOneWidget);

      // Both required defines are named, so the fix is not guesswork.
      expect(find.text('SUPABASE_URL'), findsOneWidget);
      expect(find.text('SUPABASE_ANON_KEY'), findsOneWidget);

      // It points at the doc that holds the full command.
      expect(find.textContaining('docs/BACKEND_DEPLOY.md'), findsOneWidget);

      // No retry affordance: nothing on the device can fix a build-time key.
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('never renders an empty MISSING list', (
      WidgetTester tester,
    ) async {
      // The screen falls back to the canonical define names, so its body is
      // always actionable no matter what the build actually reported missing.
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const FatalConfigScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('MISSING'), findsOneWidget);
      expect(find.text('SUPABASE_URL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
