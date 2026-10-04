import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'services.dart';

/// Auth state for the whole app.
///
/// In **mock mode** the demo user is signed in synchronously, so an unconfigured checkout still
/// boots straight to the Guard screen with seeded accounts (the Phase 0 exit criterion). In live
/// mode nothing is assumed and the router redirects to /auth until a real session exists.
class AuthNotifier extends StateNotifier<AppUser?> {
  AuthNotifier(this._repo, {required bool autoSignIn})
      : super(
          autoSignIn
              ? const AppUser(
                  id: MockAuthRepository.demoId,
                  email: MockAuthRepository.demoEmail,
                )
              : null,
        ) {
    unawaited(_bootstrap(autoSignIn));
  }

  final AuthRepository _repo;
  StreamSubscription<AppUser?>? _sub;

  bool _busy = false;
  bool get busy => _busy;

  String? _error;
  String? get error => _error;

  bool _confirmationSent = false;
  bool get confirmationSent => _confirmationSent;

  Future<void> _bootstrap(bool autoSignIn) async {
    if (autoSignIn) return; // already signed in as the demo user
    state = _repo.currentUser;
    _sub = _repo.authStateChanges().listen((AppUser? u) => state = u);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }

  Future<AuthOutcome> signIn(String email, String password) =>
      _run(() => _repo.signIn(email, password));

  Future<AuthOutcome> signUp(String email, String password) =>
      _run(() => _repo.signUp(email, password));

  Future<AuthOutcome> sendPasswordReset(String email) =>
      _run(() => _repo.sendPasswordReset(email));

  Future<void> signOut() async {
    await _repo.signOut();
    _error = null;
    _confirmationSent = false;
    state = null;
  }

  Future<AuthOutcome> _run(Future<AuthOutcome> Function() action) async {
    _busy = true;
    _error = null;
    _confirmationSent = false;
    try {
      final AuthOutcome outcome = await action();
      state = outcome.user ?? state;
      _error = outcome.error;
      _confirmationSent = outcome.needsEmailConfirmation;
      return outcome;
    } finally {
      _busy = false;
    }
  }
}

final StateNotifierProvider<AuthNotifier, AppUser?> authProvider =
    StateNotifierProvider<AuthNotifier, AppUser?>(
  (Ref ref) => AuthNotifier(
    Services.instance.auth,
    autoSignIn: Services.instance.isMock,
  ),
);
