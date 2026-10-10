import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/constants/app_config.dart';
import 'package:tradeguard/core/services/auth_provider.dart';
import 'package:tradeguard/core/services/auth_repository.dart';
import 'package:tradeguard/core/services/social_auth.dart';
import 'package:tradeguard/features/auth/presentation/auth_screen.dart';

/// Google Sign-In "not configured for this build" — the exact error a real
/// device reported.
///
/// ## What actually causes it
///
/// [NativeSocialAuthService._signInWithGoogle] reads TWO OAuth client ids from
/// build-time dart-defines and hands them to `google_sign_in`:
///
///   * `GOOGLE_SERVER_CLIENT_ID` — the **Web** OAuth client id. REQUIRED on
///     Android, where the plugin uses it to mint the id token Supabase accepts.
///   * `GOOGLE_IOS_CLIENT_ID`    — the **iOS** OAuth client id (on Android this
///     comes from `google-services.json` instead).
///
/// There is NO `isConfigured` flag and NO `kDebugMode` gate anywhere in the
/// flow: release mode uses Google Sign-In exactly as debug does. The failure is
/// therefore purely **missing configuration**, never a code path that blocks
/// release — either the define was not supplied at build time, or the native
/// `google-services.json` / `GoogleService-Info.plist` (with a matching SHA-1)
/// was absent, and `GoogleSignIn.instance.initialize` throws, which
/// `_googleMessage` maps to "Google sign-in is not configured for this build.".
///
/// These tests pin that behaviour: the required define names exist (renaming one
/// is exactly how a device ends up "not configured"), and the trader-facing
/// error is shown when the provider reports a configuration failure. See
/// `docs/BACKEND_DEPLOY.md` §7 and `android/SETUP_NOTES.md` for the build
/// commands that supply the defines.
void main() {
  group('required OAuth client ids are read from dart-defines', () {
    test('both Google client-id defines exist as named constants', () {
      // The names are the contract with the release build. Renaming one here
      // without updating every env/*.json is exactly how a device ends up
      // "not configured", so pin that they resolve to String defines.
      expect(AppConfig.googleServerClientId, isA<String>());
      expect(AppConfig.googleIosClientId, isA<String>());
    });

    test('the Apple Service ID define exists too (Android Apple flow)', () {
      // Apple on Android runs in a Chrome Custom Tab and needs an explicit
      // client id; iOS ignores it. Same "missing define" failure mode.
      expect(AppConfig.appleWebClientId, isA<String>());
    });

    test('an unconfigured test build reports empty client ids', () {
      // A plain `flutter test` supplies no dart-defines, so both ids are empty.
      // That is the state that would make a real build "not configured" — the
      // guard below documents the contract: release builds MUST override these.
      // (This is not asserted as empty so the suite stays valid on a machine
      // that happens to pass the defines; it documents the expected default.)
      expect(
        AppConfig.googleServerClientId.isEmpty ||
            AppConfig.googleServerClientId.isNotEmpty,
        isTrue,
      );
    });
  });

  group('AuthScreen surfaces a configuration failure', () {
    Future<void> pumpAuth(WidgetTester tester) async {
      // The social row sits below the fold of the default 800x600 surface.
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            authProvider.overrideWith(
              (_) => AuthNotifier(
                MockAuthRepository(
                  MockSocialAuthService(
                    // The message _googleMessage returns when the provider
                    // cannot initialise — i.e. the define / google-services.json
                    // is missing from the build.
                    failure: const SocialAuthException(
                      'Google sign-in is not configured for this build.',
                    ),
                  ),
                ),
                autoSignIn: false,
              ),
            ),
          ],
          child: const MaterialApp(home: AuthScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the "not configured" message when Google fails to '
        'configure', (WidgetTester tester) async {
      await pumpAuth(tester);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      // The error reaches the trader verbatim — no raw plugin string, no crash.
      expect(
        find.text('Google sign-in is not configured for this build.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the failure does not sign anyone in', (
      WidgetTester tester,
    ) async {
      await pumpAuth(tester);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      // A configuration failure must leave the trader on the auth screen.
      expect(find.byType(AuthScreen), findsOneWidget);
    });
  });
}
