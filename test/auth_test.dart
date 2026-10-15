import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/services/auth_error_guard.dart';
import 'package:tradeguard/core/services/auth_provider.dart';
import 'package:tradeguard/core/services/auth_repository.dart';
import 'package:tradeguard/core/services/services.dart';

/// A fake repository whose auth stream emits a background-network error,
/// mimicking GoTrue's auto-refresh failing while Android restricts network
/// access (`AuthRetryableFetchException` wrapping `SocketException:
/// Failed host lookup`).
class _FailingRefreshRepository implements AuthRepository {
  _FailingRefreshRepository(this._error);

  final Object _error;
  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();

  @override
  AppUser? get currentUser =>
      const AppUser(id: 'live-user', email: 'trader@example.com');

  @override
  Stream<AppUser?> authStateChanges() {
    scheduleMicrotask(() => _controller.addError(_error));
    return _controller.stream;
  }

  @override
  Future<AuthOutcome> signIn(String email, String password) =>
      throw UnimplementedError();

  @override
  Future<AuthOutcome> signUp(String email, String password) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<AuthOutcome> sendPasswordReset(String email) =>
      throw UnimplementedError();

  @override
  Future<AuthOutcome> signInWithProvider(_) => throw UnimplementedError();

  Future<void> close() => _controller.close();
}

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
      final AuthOutcome outcome = await repo.signIn('trader@example.com', '');
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

    test('a failed sign-in records the error and keeps the user null',
        () async {
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

  group('background auth refresh network guard', () {
    test('recognises SocketException and the retryable wrapper', () {
      expect(
        isBackgroundNetworkError(
          const SocketException('Failed host lookup: \'xyz.supabase.co\''),
        ),
        isTrue,
      );
      // gotrue wraps the socket failure in AuthRetryableFetchException whose
      // toString() always names the wrapper; the guard matches it without a
      // hard gotrue import so no real exception instance is needed here.
      expect(
        isBackgroundNetworkError(
          'AuthRetryableFetchException(message: SocketException: '
          'Failed host lookup: \'xyz.supabase.co\')',
        ),
        isTrue,
      );
    });

    test('does not mistake a real auth failure for a network blip', () {
      expect(
        isBackgroundNetworkError(
          'AuthException(message: Invalid login credentials)',
        ),
        isFalse,
      );
      expect(isBackgroundNetworkError(StateError('bad state')), isFalse);
    });

    test('AuthNotifier survives a background refresh network error', () async {
      final repo = _FailingRefreshRepository(
        const SocketException('Failed host lookup: \'xyz.supabase.co\''),
      );
      addTearDown(repo.close);
      // runZonedGuarded proves the stream error is swallowed: without the
      // onError handler it would escape here as an uncaught zone error.
      Object? zoneError;
      await runZonedGuarded(() async {
        final AuthNotifier notifier = AuthNotifier(repo, autoSignIn: false);
        addTearDown(notifier.dispose);
        // Let the microtask emitting the stream error run.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        // The user stays signed in: no crash, no silent logout.
        expect(notifier.state?.email, 'trader@example.com');
      }, (Object error, StackTrace stack) {
        zoneError = error;
      });
      expect(zoneError, isNull);
    });
  });
}
