import '../domain/delete_account.dart';
import 'delete_account_repository.dart';

/// Offline stub for the `delete-account` Edge Function.
///
/// In mock mode there is no backend to delete from, so this records the request and resolves —
/// the destructive confirmation UI is fully exercisable without a project. It never contacts a
/// network and never removes anything real. Tests inject [failure] to exercise the error path.
class MockDeleteAccountRepository implements DeleteAccountRepository {
  MockDeleteAccountRepository({this.failure});

  /// When set, [deleteAccount] throws this instead of resolving — drives the failure UI in tests.
  final DeleteAccountException? failure;

  /// How many times [deleteAccount] was called, so a test can assert the confirm actually fired.
  int callCount = 0;

  @override
  bool get isStubbed => true;

  @override
  Future<void> deleteAccount() async {
    callCount++;
    final DeleteAccountException? failure = this.failure;
    if (failure != null) throw failure;
  }
}
