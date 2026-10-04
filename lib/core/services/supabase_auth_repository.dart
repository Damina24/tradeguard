import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';
import 'social_auth.dart';
import 'supabase_service.dart';

/// Supabase-backed auth. Provider messages are translated into copy we are happy to show a
/// trader — raw exceptions never reach the UI.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository([SupabaseService? service, SocialAuthService? social])
      : _service = service ?? SupabaseService.instance,
        _social = social ?? NativeSocialAuthService();

  final SupabaseService _service;

  /// Owns the platform SDKs. Injected so tests never touch a platform channel.
  final SocialAuthService _social;

  SupabaseClient get _client => _service.client;

  @override
  AppUser? get currentUser {
    final User? u = _client.auth.currentUser;
    return u == null ? null : _toUser(u);
  }

  @override
  Stream<AppUser?> authStateChanges() => _client.auth.onAuthStateChange.map(
        (AuthState state) =>
            state.session == null ? null : _toUser(state.session!.user),
      );

  @override
  Future<AuthOutcome> signIn(String email, String password) async {
    try {
      final AuthResponse res = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final User? user = res.user;
      if (user == null) {
        return const AuthOutcome.failure('Sign-in failed. Check your details.');
      }
      return AuthOutcome.success(_toUser(user));
    } on AuthException catch (e) {
      return AuthOutcome.failure(_friendly(e.message));
    } catch (_) {
      return const AuthOutcome.failure('Could not reach the server. Try again.');
    }
  }

  @override
  Future<AuthOutcome> signUp(String email, String password) async {
    try {
      final AuthResponse res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      final User? user = res.user;
      if (user == null) {
        return const AuthOutcome.failure('Could not create that account.');
      }
      // A live session means email confirmation is disabled and we are already signed in.
      if (res.session != null) return AuthOutcome.success(_toUser(user));
      return const AuthOutcome.confirmationRequired();
    } on AuthException catch (e) {
      return AuthOutcome.failure(_friendly(e.message));
    } catch (_) {
      return const AuthOutcome.failure('Could not reach the server. Try again.');
    }
  }

  @override
  Future<void> signOut() async {
    // Clear the provider's cached account too, otherwise the next tap re-opens a picker for a
    // session that no longer exists in Supabase.
    await _social.signOut();
    await _client.auth.signOut();
  }

  @override
  Future<AuthOutcome> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
      return const AuthOutcome.done();
    } on AuthException catch (e) {
      return AuthOutcome.failure(_friendly(e.message));
    } catch (_) {
      return const AuthOutcome.failure('Could not reach the server. Try again.');
    }
  }

  @override
  Future<AuthOutcome> signInWithProvider(SocialProvider provider) async {
    try {
      final SocialAuthResult result = await _social.signIn(provider);
      final SocialCredential? credential = result.credential;
      // The trader closed the Apple/Google sheet: success, no user, no error banner.
      if (credential == null) return const AuthOutcome.done();

      // Supabase verifies the signature and `aud`/`iss` of the ID token before it issues a
      // session, so the client never decides who the user is.
      final AuthResponse res = await _client.auth.signInWithIdToken(
        provider: _oauthProvider(provider),
        idToken: credential.idToken,
        accessToken: credential.accessToken,
        nonce: credential.nonce,
      );
      final User? user = res.user;
      if (user == null) {
        return AuthOutcome.failure(
          provider == SocialProvider.apple
              ? 'Apple sign-in failed. Try again.'
              : 'Google sign-in failed. Try again.',
        );
      }
      return AuthOutcome.success(_toUser(user));
    } on SocialAuthException catch (e) {
      return AuthOutcome.failure(e.message);
    } on AuthException catch (e) {
      return AuthOutcome.failure(_friendlyIdToken(e.message));
    } catch (_) {
      return const AuthOutcome.failure('Could not reach the server. Try again.');
    }
  }

  static OAuthProvider _oauthProvider(SocialProvider provider) =>
      provider == SocialProvider.apple ? OAuthProvider.apple : OAuthProvider.google;

  static AppUser _toUser(User u) => AppUser(
        id: u.id,
        email: u.email,
        plan: (u.userMetadata?['plan'] as String?) ?? 'free',
      );

  /// Maps raw provider messages onto trader-friendly copy.
  static String _friendly(String raw) {
    final String m = raw.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'Wrong email or password.';
    }
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'That email is already registered. Try signing in.';
    }
    if (m.contains('password should be')) {
      return 'Choose a longer password (at least 6 characters).';
    }
    if (m.contains('email not confirmed')) {
      return 'Confirm your email first — check your inbox.';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Too many attempts. Wait a moment and try again.';
    }
    return 'Something went wrong. Try again.';
  }

  /// GoTrue's `signInWithIdToken` failures are configuration problems far more often than user
  /// mistakes, so each known shape gets copy that names the fix instead of leaking the token error.
  static String _friendlyIdToken(String raw) {
    final String m = raw.toLowerCase();
    if (m.contains('invalid id token') ||
        m.contains('jwt') ||
        m.contains('signature')) {
      return 'That social sign-in could not be verified. Try again.';
    }
    if (m.contains('nonce')) {
      return 'Sign-in expired. Please try again.';
    }
    if (m.contains('provider is not enabled') ||
        m.contains('provider not enabled')) {
      return 'That sign-in method is not enabled yet.';
    }
    if (m.contains('aud')) {
      return 'This app is not registered for that sign-in provider yet.';
    }
    if (m.contains('user not found') || m.contains('does not exist')) {
      return 'No account was found for that identity.';
    }
    return _friendly(raw);
  }
}
