import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';
import 'supabase_service.dart';

/// Supabase-backed auth. Provider messages are translated into copy we are happy to show a
/// trader — raw exceptions never reach the UI.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository([SupabaseService? service])
      : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

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
}
