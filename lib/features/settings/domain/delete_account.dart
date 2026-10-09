/// The outcome vocabulary for the in-app account-deletion flow.
///
/// The client never decides whether a deletion happened: it asks the `delete-account` Edge
/// Function, which authenticates the caller with GoTrue, deletes the caller's rows child-first,
/// removes their `trade-screenshots` objects by uid prefix and finally removes the auth user. This
/// seam only reports success or a trader-safe failure — a raw PostgREST error can name tables and
/// columns, and nothing it says is worth showing a trader, so it never reaches the UI.
library;

/// Why an account-deletion request could not be completed.
///
/// Every message is trader-safe copy: no server text, no table names, no uid. Mapped from the Edge
/// Function's HTTP status / safe error token, exactly as `CopySignalFailure` is for copy-signal.
enum DeleteAccountFailure {
  unreachable('Could not reach the server — check your connection and try again.'),
  unauthorized('Sign in again to delete your account.'),
  forbidden('That request is not available.'),
  unavailable('The account service is unavailable — try again.'),
  notConfigured('Account deletion is not available in this build.'),
  server('We could not delete your account right now. Please try again.');

  const DeleteAccountFailure(this.message);

  final String message;
}

/// A failed call to the `delete-account` Edge Function.
///
/// Carries a [DeleteAccountFailure], never a raw server message.
class DeleteAccountException implements Exception {
  const DeleteAccountException(this.failure);

  final DeleteAccountFailure failure;

  String get message => failure.message;

  @override
  String toString() => 'DeleteAccountException($failure)';
}
