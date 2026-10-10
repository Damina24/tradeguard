import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/services/auth_provider.dart';
import 'package:tradeguard/core/services/auth_repository.dart';
import 'package:tradeguard/core/services/social_auth.dart';
import 'package:tradeguard/features/auth/presentation/auth_screen.dart';

void main() {
  group('NativeSocialAuthService.sha256of', () {
    test('matches the published SHA-256 of "abc"', () {
      // Apple rejects a nonce whose digest does not match, so this has to be real SHA-256.
      expect(
        NativeSocialAuthService.sha256of('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('is stable for an empty nonce', () {
      expect(
        NativeSocialAuthService.sha256of(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });
  });

  group('MockSocialAuthService', () {
    test('returns a credential and records the attempt', () async {
      final MockSocialAuthService social = MockSocialAuthService();
      final SocialAuthResult result =
          await social.signIn(SocialProvider.google);

      expect(result.isSuccess, isTrue);
      expect(result.cancelled, isFalse);
      expect(result.credential?.provider, SocialProvider.google);
      expect(result.credential?.idToken, isNotEmpty);
      expect(social.attempts, <SocialProvider>[SocialProvider.google]);
    });

    test('a dismissed sheet is a distinct state, not a failure', () async {
      final MockSocialAuthService social =
          MockSocialAuthService(dismiss: true);
      final SocialAuthResult result =
          await social.signIn(SocialProvider.apple);

      expect(result.cancelled, isTrue);
      expect(result.credential, isNull);
    });

    test('propagates a configured failure', () async {
      final MockSocialAuthService social = MockSocialAuthService(
        failure: const SocialAuthException('Not configured.'),
      );
      await expectLater(
        social.signIn(SocialProvider.apple),
        throwsA(isA<SocialAuthException>()),
      );
    });
  });

  group('googleSignInHint', () {
    test('code 7 maps to a connectivity hint', () {
      expect(googleSignInHint('7'), 'Check your connection and retry');
    });

    test('codes 10, 12500 and 12502 map to a setup hint', () {
      for (final String code in <String>['10', '12500', '12502']) {
        expect(
          googleSignInHint(code),
          'Sign-in setup issue; contact support with this code',
          reason: code,
        );
      }
    });

    test('testing-track codes map to an enablement hint', () {
      for (final String code in <String>['403', 'access_denied']) {
        expect(
          googleSignInHint(code),
          'This Google account is not enabled for testing yet',
          reason: code,
        );
      }
    });

    test('unknown or missing codes fall back to generic copy', () {
      expect(googleSignInHint('bogus'), isNull);
      expect(googleSignInHint(null), isNull);
    });
  });

  group('MockAuthRepository.signInWithProvider', () {
    test('signs the demo trader in through the provider', () async {
      final MockSocialAuthService social = MockSocialAuthService();
      final MockAuthRepository repo = MockAuthRepository(social);

      await repo.signOut();
      final AuthOutcome outcome =
          await repo.signInWithProvider(SocialProvider.apple);

      expect(outcome.isSuccess, isTrue);
      expect(outcome.error, isNull);
      expect(outcome.user?.id, 'demo-apple');
      expect(repo.currentUser?.email, 'apple@demo.tradeguard.app');
    });

    test('a dismissed sheet reports success with no user and no error', () async {
      final MockAuthRepository repo =
          MockAuthRepository(MockSocialAuthService(dismiss: true));
      await repo.signOut();

      final AuthOutcome outcome =
          await repo.signInWithProvider(SocialProvider.apple);

      expect(outcome.isSuccess, isTrue);
      expect(outcome.user, isNull);
      expect(outcome.error, isNull);
      expect(repo.currentUser, isNull);
    });

    test('surfaces a provider failure as friendly copy', () async {
      final MockAuthRepository repo = MockAuthRepository(
        MockSocialAuthService(
          failure: const SocialAuthException('Google sign-in failed. Try again.'),
        ),
      );
      await repo.signOut();

      final AuthOutcome outcome =
          await repo.signInWithProvider(SocialProvider.google);

      expect(outcome.isSuccess, isFalse);
      expect(outcome.error, 'Google sign-in failed. Try again.');
      expect(repo.currentUser, isNull);
    });
  });

  group('authProvider.signInWithProvider', () {
    test('publishes the signed-in user', () async {
      final MockSocialAuthService social = MockSocialAuthService();
      final container = ProviderContainer(
        overrides: <Override>[
          authProvider.overrideWith(
            (_) => AuthNotifier(
              MockAuthRepository(social),
              autoSignIn: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // MockAuthRepository starts signed in as the demo trader, so sign out first.
      await container.read(authProvider.notifier).signOut();
      expect(container.read(authProvider), isNull);
      final AuthOutcome outcome = await container
          .read(authProvider.notifier)
          .signInWithProvider(SocialProvider.google);

      expect(outcome.isSuccess, isTrue);
      expect(container.read(authProvider)?.id, 'demo-google');
      expect(social.attempts, <SocialProvider>[SocialProvider.google]);
    });

    test('a dismissal leaves the user signed out and sets no error', () async {
      final container = ProviderContainer(
        overrides: <Override>[
          authProvider.overrideWith(
            (_) => AuthNotifier(
              MockAuthRepository(MockSocialAuthService(dismiss: true)),
              autoSignIn: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).signOut();
      await container
          .read(authProvider.notifier)
          .signInWithProvider(SocialProvider.apple);

      expect(container.read(authProvider), isNull);
      expect(container.read(authProvider.notifier).error, isNull);
    });
  });

  group('AuthScreen social buttons', () {
    Future<MockSocialAuthService> pumpAuth(
      WidgetTester tester, {
      MockSocialAuthService? social,
    }) async {
      final MockSocialAuthService service = social ?? MockSocialAuthService();
      // The social row sits below the form, past the fold of the default 800x600 surface.
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            authProvider.overrideWith(
              (_) => AuthNotifier(
                MockAuthRepository(service),
                autoSignIn: false,
              ),
            ),
          ],
          child: const MaterialApp(home: AuthScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return service;
    }

    testWidgets('renders both providers below the form', (
      WidgetTester tester,
    ) async {
      await pumpAuth(tester);

      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('or'), findsOneWidget);
    });

    testWidgets('tapping Google routes through the social service', (
      WidgetTester tester,
    ) async {
      final MockSocialAuthService social = await pumpAuth(tester);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(social.attempts, <SocialProvider>[SocialProvider.google]);
    });

    testWidgets('a dismissed sheet shows no error banner', (
      WidgetTester tester,
    ) async {
      await pumpAuth(tester, social: MockSocialAuthService(dismiss: true));

      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();

      // The form is still there and no red copy was produced.
      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(find.textContaining('Try again'), findsNothing);
      expect(find.textContaining('not configured'), findsNothing);
    });

    testWidgets('a provider failure is shown to the trader', (
      WidgetTester tester,
    ) async {
      await pumpAuth(
        tester,
        social: MockSocialAuthService(
          failure: const SocialAuthException('Google sign-in failed. Try again.'),
        ),
      );

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(find.text('Google sign-in failed. Try again.'), findsOneWidget);
    });
  });
}