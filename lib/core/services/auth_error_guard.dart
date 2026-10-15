import 'dart:io';

import 'package:flutter/foundation.dart';

/// Distinguishes a transient background-network failure during a Supabase
/// GoTrue token refresh from a real auth problem.
///
/// When Android (especially Samsung's power manager) restricts network access
/// while the app is backgrounded, the GoTrue auto-refresh ticker fails its
/// `/token` call. `GotrueFetch` wraps the underlying `SocketException`
/// (`Failed host lookup ...`) in an `AuthRetryableFetchException` and emits
/// it as a stream error on `onAuthStateChange` — and, for the recovery path,
/// rethrows it so it can also surface in the root zone. Without an `onError`
/// handler Dart turns that stream error into an unhandled zone exception and
/// the VM crashes (the Crashlytics `AuthRetryableFetchException` reports).
///
/// The SDK retries the refresh on its own when the app returns to the
/// foreground, so the only correct handling here is: log quietly, keep the
/// existing session, never rethrow, never sign the user out.
bool isBackgroundNetworkError(Object error) {
  if (error is SocketException) return true;
  // Avoid a hard dependency on gotrue types here (this file is imported by
  // the provider and `main`): the retryable wrapper always names itself in
  // `toString()`, and always embeds the underlying socket failure.
  final String text = error.toString();
  if (text.contains('AuthRetryableFetchException')) return true;
  const List<String> markers = <String>[
    'SocketException',
    'Failed host lookup',
    'Network is unreachable',
    'No address associated with hostname',
    'Connection reset by peer',
    'Connection refused',
    'Software caused connection abort',
  ];
  for (final String marker in markers) {
    if (text.contains(marker)) return true;
  }
  return false;
}

/// Logs a background refresh failure without crashing or signing out.
///
/// Must be called from every `onAuthStateChange` `onError` handler and from
/// the root-zone guard in `main.dart`. Network blips log the canonical
/// one-liner and are swallowed; anything else is logged with its detail so
/// it stays visible in debug output but still never escapes as fatal.
void handleBackgroundAuthError(Object error, [StackTrace? stackTrace]) {
  if (isBackgroundNetworkError(error)) {
    debugPrint(
      'Background auth refresh deferred: Network unavailable or restricted.',
    );
    return;
  }
  debugPrint('Auth stream error (non-network): $error');
}
