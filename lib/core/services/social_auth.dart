import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../constants/app_config.dart';

/// Identity providers offered next to email + password (Phase 1, task 1.1).
enum SocialProvider {
  apple('Apple'),
  google('Google');

  const SocialProvider(this.label);

  /// Label used on the button and in error copy.
  final String label;
}

/// A verified OIDC assertion handed to Supabase.
///
/// Only [idToken] is trusted: [email] / [displayName] are display hints (Apple returns them just
/// once, and never for a returning user), and Supabase re-validates the token server-side before it
/// issues a session. No credential from here is ever stored on the device.
class SocialCredential {
  const SocialCredential({
    required this.provider,
    required this.idToken,
    this.accessToken,
    this.email,
    this.displayName,
    this.nonce,
  });

  final SocialProvider provider;

  /// The provider's signed ID token — the only value with any authority.
  final String idToken;
  final String? accessToken;
  final String? email;
  final String? displayName;

  /// The **raw** (unhashed) nonce generated for Apple. Supabase re-derives the hash from this value
  /// and compares it against the token's `nonce_salt`, so it must be the pre-image — never the hash
  /// that was sent to Apple.
  final String? nonce;
}

/// Outcome of a social sign-in attempt.
///
/// Dismissing the system sheet is modelled explicitly rather than as an error, because "the trader
/// closed the popup" must never paint a red message on the auth screen.
class SocialAuthResult {
  const SocialAuthResult.credential(this.credential) : cancelled = false;

  const SocialAuthResult.cancelled() : credential = null, cancelled = true;

  final SocialCredential? credential;
  final bool cancelled;

  bool get isSuccess => credential != null;
}

/// A sign-in failure whose [message] is safe to render for a trader. Plugin exceptions are mapped
/// onto these, so no provider string is ever shown verbatim.
class SocialAuthException implements Exception {
  const SocialAuthException(this.message);

  final String message;

  @override
  String toString() => 'SocialAuthException: $message';
}

/// Platform-level social sign-in. Split out from the auth repository so repositories stay free of
/// plugin imports and the whole flow is testable without platform channels.
abstract class SocialAuthService {
  /// Throws [SocialAuthException] on failure; returns [SocialAuthResult.cancelled] when the trader
  /// dismisses the sheet.
  Future<SocialAuthResult> signIn(SocialProvider provider);

  /// Clears the provider's local session. Must never throw.
  Future<void> signOut();
}

/// Real implementation over `sign_in_with_apple` + `google_sign_in`.
///
/// Every failure mode is caught and re-thrown as a [SocialAuthException], because these packages
/// throw a mix of `PlatformException`, their own exception types, and raw strings.
class NativeSocialAuthService implements SocialAuthService {
  NativeSocialAuthService();

  @override
  Future<SocialAuthResult> signIn(SocialProvider provider) async {
    switch (provider) {
      case SocialProvider.apple:
        return _signInWithApple();
      case SocialProvider.google:
        return _signInWithGoogle();
    }
  }

  Future<SocialAuthResult> _signInWithApple() async {
    // Android runs the Apple flow in a Chrome Custom Tab and needs an explicit client id +
    // redirect; iOS ignores these and only needs the capability enabled in Xcode.
    final bool viaWeb = defaultTargetPlatform == TargetPlatform.android;
    if (viaWeb &&
        (AppConfig.appleWebClientId.isEmpty || AppConfig.supabaseUrl.isEmpty)) {
      throw const SocialAuthException(
        'Apple sign-in is not configured for this build.',
      );
    }

    final String rawNonce = generateNonce();
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const <AppleIDAuthorizationScopes>[
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256of(rawNonce),
        webAuthenticationOptions: viaWeb
            ? WebAuthenticationOptions(
                clientId: AppConfig.appleWebClientId,
                redirectUri:
                    Uri.parse('${AppConfig.supabaseUrl}/auth/v1/callback'),
              )
            : null,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const SocialAuthResult.cancelled();
      }
      throw SocialAuthException(_appleMessage(e.code));
    } on SignInWithAppleNotSupportedException {
      throw const SocialAuthException(
        'Sign in with Apple is not available on this device.',
      );
    } on SignInWithAppleException {
      throw const SocialAuthException('Apple sign-in failed. Try again.');
    }

    final String? idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw const SocialAuthException(
        'Apple did not return a usable identity token.',
      );
    }

    return SocialAuthResult.credential(
      SocialCredential(
        provider: SocialProvider.apple,
        idToken: idToken,
        email: credential.email,
        displayName: _joinName(credential.givenName, credential.familyName),
        nonce: rawNonce,
      ),
    );
  }

  Future<SocialAuthResult> _signInWithGoogle() async {
    final GoogleSignIn signIn = GoogleSignIn.instance;
    try {
      await signIn.initialize(
        clientId: AppConfig.googleIosClientId.isEmpty
            ? null
            : AppConfig.googleIosClientId,
        serverClientId: AppConfig.googleServerClientId.isEmpty
            ? null
            : AppConfig.googleServerClientId,
      );
    } on GoogleSignInException catch (e) {
      throw SocialAuthException(_googleMessage(e.code));
    } catch (_) {
      // No `google-services.json` / `GoogleService-Info.plist`, or an unusable SHA-1 fingerprint.
      throw const SocialAuthException(
        'Google sign-in is not configured for this build.',
      );
    }

    if (!signIn.supportsAuthenticate()) {
      throw const SocialAuthException(
        'Google sign-in is not available on this device.',
      );
    }

    try {
      final GoogleSignInAccount account = await signIn.authenticate();
      final String? idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const SocialAuthException(
          'Google did not return a usable identity token.',
        );
      }
      return SocialAuthResult.credential(
        SocialCredential(
          provider: SocialProvider.google,
          idToken: idToken,
          email: account.email,
          displayName: account.displayName,
        ),
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const SocialAuthResult.cancelled();
      }
      throw SocialAuthException(_googleMessage(e.code));
    } on SocialAuthException {
      rethrow;
    } catch (_) {
      throw const SocialAuthException('Google sign-in failed. Try again.');
    }
  }

  /// Apple has no local session to clear — Supabase owns ours.
  @override
  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Signing out of the app must never fail because a provider felt awkward.
    }
  }

  /// SHA-256 of the nonce, which is what Apple expects in `nonce`.
  static String sha256of(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static String? _joinName(String? given, String? family) {
    final String name = <String?>[given, family]
        .whereType<String>()
        .where((String part) => part.trim().isNotEmpty)
        .join(' ')
        .trim();
    return name.isEmpty ? null : name;
  }

  static String _appleMessage(AuthorizationErrorCode code) {
    switch (code) {
      case AuthorizationErrorCode.notHandled:
        return 'Apple sign-in could not start. Try again.';
      case AuthorizationErrorCode.invalidResponse:
        return 'Apple returned an unexpected response. Try again.';
      case AuthorizationErrorCode.failed:
      case AuthorizationErrorCode.unknown:
        return 'Apple sign-in failed. Try again.';
      case AuthorizationErrorCode.notInteractive:
        return 'Apple sign-in needs an open app window.';
      case AuthorizationErrorCode.credentialExport:
      case AuthorizationErrorCode.credentialImport:
      case AuthorizationErrorCode.matchedExcludedCredential:
      case AuthorizationErrorCode.canceled:
        return 'Apple sign-in is unavailable right now.';
    }
  }

  static String _googleMessage(GoogleSignInExceptionCode code) {
    switch (code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Google sign-in cancelled.';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google sign-in is not configured for this build.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Google sign-in needs an open app window.';
      case GoogleSignInExceptionCode.userMismatch:
        return 'That Google account is not the signed-in one.';
      case GoogleSignInExceptionCode.interrupted:
      case GoogleSignInExceptionCode.unknownError:
        return 'Google sign-in failed. Try again.';
    }
  }
}

/// Offline social sign-in, so the buttons stay exercisable in mock mode and in tests.
class MockSocialAuthService implements SocialAuthService {
  MockSocialAuthService({this.failure, this.dismiss = false});

  /// When set, every attempt throws this instead of returning a credential.
  SocialAuthException? failure;

  /// When true the attempt behaves like a trader dismissing the system sheet.
  bool dismiss;

  /// Providers the UI asked for, in order.
  final List<SocialProvider> attempts = <SocialProvider>[];

  @override
  Future<SocialAuthResult> signIn(SocialProvider provider) async {
    attempts.add(provider);
    if (dismiss) return const SocialAuthResult.cancelled();
    final SocialAuthException? failure = this.failure;
    if (failure != null) throw failure;
    return SocialAuthResult.credential(
      SocialCredential(
        provider: provider,
        idToken: 'mock-${provider.name}-id-token',
        email: '${provider.name}@demo.tradeguard.app',
        displayName: 'Demo ${provider.label} Trader',
      ),
    );
  }

  @override
  Future<void> signOut() async {}
}