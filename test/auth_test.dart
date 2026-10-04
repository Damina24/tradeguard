import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/services/auth_provider.dart';
import 'package:tradeguard/core/services/auth_repository.dart';
import 'package:tradeguard/core/services/services.dart';

void main() {
  group('MockAuthRepository', () {
    test('starts signed in as the demo trader', () {
      final MockAuthRepository repo = MockAuthRepository();
      expect(repo.currentUser?.email, MockAuthRepository.demoEmail);
    });

    test('rejects a malformed email', () async {
      final MockAuthRepository repo = MockAuthRepository();
      final AuthOutcome outcome = await repo.signIn('not-an-email', 'secret');
      expect(outcome.isSuccess, isFalse);
      expect(outcome.user, isNull);
      expect(outcome.error, isNotEmpty);
    });

    test('rejects an empty password', () async {
      final MockAuthRepository repo = MockAuthRepository();
      final AuthOutcome outcome =
          await repo.signIn('trader@example.com', '');
      expect(outcome.isSuccess, isFalse);
    });

    test('signs in and normalises the email', () async {
      final MockAuthRepository repo = MockAuthRepository();
      final AuthOutcome outcome =
          await repo.signIn('  Trader@Example.COM ', 'secret');
      expect(outcome.isSuccess, isTrue);
      expect(outcome.user?.email, 'trader@example.com');
      expect(repo.currentUser?.email, 'trader@example.com');
    });

    test('sign out clears the session', () async {
      final MockAuthRepository repo = MockAuthRepository();
      await repo.signOut();
      expect(repo.currentUser, isNull);
    });

    test('password reset validates the email', () async {
      final MockAuthRepository repo = MockAuthRepository();
      expect((await repo.sendPasswordReset('bad')).isSuccess, isFalse);
      expect(
        (await repo.sendPasswordReset('trader@example.com')).isSuccess,
        isTrue,
      );
    });
  });

  group('AuthOutcome', () {
    test('confirmationRequired is a success that carries no user', () {
      const AuthOutcome outcome = AuthOutcome.confirmationRequired();
      expect(outcome.isSuccess, isTrue);
      expect(outcome.needsEmailConfirmation, isTrue);
      expect(outcome.user, isNull);
    });

    test('failure is not a success', () {
      const AuthOutcome outcome = AuthOutcome.failure('nope');
      expect(outcome.isSuccess, isFalse);
      expect(outcome.error, 'nope');
    });
  });

  group('authProvider in mock mode', () {
    test('auto-signs-in so the app still boots to Guard', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(authProvider)?.email, MockAuthRepository.demoEmail);
    });

    test('signOut clears the signed-in user', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(authProvider.notifier).signOut();
      expect(container.read(authProvider), isNull);
    });

    test('a failed sign-in records the error and keeps the user null', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(authProvider.notifier).signOut();
      final outcome =
          await container.read(authProvider.notifier).signIn('bad', '');
      expect(outcome.isSuccess, isFalse);
      expect(container.read(authProvider.notifier).error, isNotEmpty);
      expect(container.read(authProvider), isNull);
    });
  });

  test('Services resolves the mock auth repository', () {
    expect(Services.instance.auth, isA<MockAuthRepository>());
  });
}
