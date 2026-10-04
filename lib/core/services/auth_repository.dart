/// Backend-agnostic representation of the signed-in user.
class AppUser {
  const AppUser({required this.id, this.email, this.plan = 'free'});

  final String id;
  final String? email;
  final String plan;
}

/// Result of an auth operation. [error] is a human-readable, non-technical message that is safe
/// to show in the UI (never surface raw Supabase exceptions).
class AuthOutcome {
  const AuthOutcome.success(this.user)
      : error = null,
        needsEmailConfirmation = false;

  const AuthOutcome.failure(this.error)
      : user = null,
        needsEmailConfirmation = false;

  /// Sign-up succeeded but the backend is waiting for the user to click a confirmation link.
  const AuthOutcome.confirmationRequired()
      : user = null,
        error = null,
        needsEmailConfirmation = true;

  /// Generic success that carries no user (e.g. "reset email sent").
  const AuthOutcome.done()
      : user = null,
        error = null,
        needsEmailConfirmation = false;

  final AppUser? user;
  final String? error;
  final bool needsEmailConfirmation;

  bool get isSuccess => error == null;
}

abstract class AuthRepository {
  AppUser? get currentUser;

  /// Emits on sign-in, sign-out and token refresh. `null` means signed out.
  Stream<AppUser?> authStateChanges();

  Future<AuthOutcome> signIn(String email, String password);

  Future<AuthOutcome> signUp(String email, String password);

  Future<void> signOut();

  Future<AuthOutcome> sendPasswordReset(String email);
}

/// Offline auth so the whole app can be exercised without a backend. Any well-formed email plus a
/// non-empty password succeeds.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository();

  static const String demoId = 'demo-user';
  static const String demoEmail = 'demo@tradeguard.app';

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  AppUser? _user = const AppUser(id: demoId, email: demoEmail);

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> authStateChanges() => Stream<AppUser?>.value(_user);

  @override
  Future<AuthOutcome> signIn(String email, String password) async {
    if (!isValidEmail(email) || password.isEmpty) {
      return const AuthOutcome.failure('Enter a valid email and password.');
    }
    _user = AppUser(id: demoId, email: email.trim().toLowerCase());
    return AuthOutcome.success(_user!);
  }

  @override
  Future<AuthOutcome> signUp(String email, String password) async =>
      signIn(email, password);

  @override
  Future<void> signOut() async {
    _user = null;
  }

  @override
  Future<AuthOutcome> sendPasswordReset(String email) async {
    if (!isValidEmail(email)) {
      return const AuthOutcome.failure('Enter a valid email address.');
    }
    return const AuthOutcome.done();
  }

  static bool isValidEmail(String email) => _emailPattern.hasMatch(email.trim());
}
