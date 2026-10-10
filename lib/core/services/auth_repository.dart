import 'social_auth.dart';

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
        code = null,
        needsEmailConfirmation = false;

  const AuthOutcome.failure(this.error, {this.code})
      : user = null,
        needsEmailConfirmation = false;

  /// Sign-up succeeded but the backend is waiting for the user to click a confirmation link.
  const AuthOutcome.confirmationRequired()
      : user = null,
        error = null,
        code = null,
        needsEmailConfirmation = true;

  /// Generic success that carries no user (e.g. "reset email sent").
  const AuthOutcome.done()
      : user = null,
        error = null,
        code = null,
        needsEmailConfirmation = false;

  final AppUser? user;
  final String? error;

  /// Raw provider failure code (Google only) attached to a social sign-in
  /// failure. `null` for every non-social outcome and for Apple. The
  /// presentation layer turns it into a Crashlytics custom key in release and a
  /// snackbar hint in debug/profile; it is never rendered to a trader verbatim.
  final String? code;

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

  /// Signs in with an Apple/Google identity token. Returns [AuthOutcome.done] — a success carrying
  /// no user — when the trader dismisses the system sheet, so nothing is shown for it.
  Future<AuthOutcome> signInWithProvider(SocialProvider provider);
}

/// Offline auth so the whole app can be exercised without a backend. Any well-formed email plus a
/// non-empty password succeeds.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository([SocialAuthService? social])
      : _social = social ?? MockSocialAuthService();

  final SocialAuthService _social;

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

  @override
  Future<AuthOutcome> signInWithProvider(SocialProvider provider) async {
    try {
      final SocialAuthResult result = await _social.signIn(provider);
      final SocialCredential? credential = result.credential;
      // Dismissing the sheet is not an error, so it must not raise a red banner.
      if (credential == null) return const AuthOutcome.done();
      _user = AppUser(
        id: 'demo-${credential.provider.name}',
        email: credential.email,
      );
      return AuthOutcome.success(_user!);
    } on SocialAuthException catch (e) {
      return AuthOutcome.failure(e.message, code: e.code);
    }
  }

  static bool isValidEmail(String email) => _emailPattern.hasMatch(email.trim());
}
