import '../domain/trade_sync.dart';

/// Where each account's sync watermark lives.
///
/// Separate from `TradeImportRepository` on purpose: that one owns *trades*, this one owns
/// *progress*. Keeping them apart means the sync cursor can be locked, retried and pruned
/// without touching the journal, and Task 2.1's boundary stays untouched.
abstract class TradeSyncCursorRepository {
  Future<TradeSyncCursor?> read(String accountId);

  Future<void> write(TradeSyncCursor cursor);

  /// Cursors for accounts eligible for syncing. Implementations MUST scope the result to the
  /// calling user when a user id is supplied — this is the boundary that prevents one trader's
  /// sync from touching another trader's accounts.
  Future<List<TradeSyncCursor>> listEligible({String? userId});
}

/// In-memory cursor store for mock mode and tests.
class InMemoryTradeSyncCursorRepository implements TradeSyncCursorRepository {
  InMemoryTradeSyncCursorRepository([List<TradeSyncCursor>? seed]) {
    for (final TradeSyncCursor c in seed ?? const <TradeSyncCursor>[]) {
      _byAccount[c.accountId] = c;
    }
  }

  final Map<String, TradeSyncCursor> _byAccount = <String, TradeSyncCursor>{};

  /// accountId -> owning user id, so scoping can be exercised in a test.
  final Map<String, String> owners = <String, String>{};

  @override
  Future<TradeSyncCursor?> read(String accountId) async => _byAccount[accountId];

  @override
  Future<void> write(TradeSyncCursor cursor) async {
    _byAccount[cursor.accountId] = cursor;
  }

  @override
  Future<List<TradeSyncCursor>> listEligible({String? userId}) async => _byAccount.values
      .where((TradeSyncCursor c) => userId == null || owners[c.accountId] == userId)
      .toList();
}