import '../domain/delete_account.dart';

/// Deletes the signed-in trader's account and all of their data through the `delete-account`
/// Edge Function (store compliance: Apple 5.1.1(v), Google Play account-deletion).
///
/// The client never performs the deletion itself and never sees which tables are touched: it asks
/// the Edge Function, which authenticates the caller with GoTrue, deletes their rows child-first,
/// removes their `trade-screenshots` objects by uid prefix and finally removes the auth user. This
/// seam only reports success or a trader-safe [DeleteAccountException].
abstract class DeleteAccountRepository {
  /// True when this is the offline stub (mock mode) rather than the real Supabase call.
  bool get isStubbed;

  /// Requests deletion of the caller's own account.
  ///
  /// Resolves when the server confirms the account and its data are gone. Throws
  /// [DeleteAccountException] with trader-safe copy on any failure — raw server text is never
  /// surfaced. The call is idempotent server-side, so a retry after a transient failure is safe.
  Future<void> deleteAccount();
}
