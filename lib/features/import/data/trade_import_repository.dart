import '../domain/import_issue.dart';
import '../domain/trade_record.dart';

/// What to do when a trade identifier is already present in the destination account.
///
/// Duplicate handling is an explicit, deterministic choice rather than an emergent side effect
/// of an upsert, because "do not silently create duplicate trades" is a data-integrity
/// requirement: a trader who imports the same statement twice must not see their P&L double.
enum DuplicateStrategy {
  /// Keep what is already stored and ignore the incoming row. Default, and the only safe
  /// choice for a re-import of a file already loaded.
  skipExisting,

  /// Overwrite the stored trade with the incoming one. Use when the broker restated a figure.
  replaceExisting,

  /// Refuse the whole import if any identifier already exists.
  fail,

  /// Keep both rows.
  ///
  /// Included only so the behaviour is a decision the app makes explicitly rather than
  /// something a caller can trigger by accident; the importer warns when it is chosen.
  allowDuplicates,
}

/// Persistence boundary for imports.
///
/// Deliberately narrow: it stores normalized [TradeRecord]s and can answer "do you already have
/// this trade identifier?". It knows nothing about CSV, HTML, brokers or MetaAPI, which is what
/// keeps `sync-trades` (Task 2.2) free to reuse the same seam.
abstract class TradeImportRepository {
  /// Trade identifiers already stored for [accountId].
  Future<Set<String>> existingExternalIds(String accountId);

  /// Persists normalized records.
  ///
  /// Implementations MUST apply [strategy] themselves and MUST NOT invent identifiers — the
  /// dedupe key is the broker's own.
  Future<int> saveTrades(
    String accountId,
    List<TradeRecord> records, {
    DuplicateStrategy strategy = DuplicateStrategy.skipExisting,
  });
}

/// In-memory implementation used in mock mode and in tests.
///
/// Seedable with existing trades so the duplicate paths are exercisable without a backend.
/// In-memory implementation used in mock mode and in tests.
///
/// Keyed by account AND external id: the same ticket in two accounts is two journal entries,
/// not a duplicate. A flat id->trade map would silently drop the second one.
///
/// Seeded records are always scoped to [seedAccount] (required when [seed] is non-empty), so
/// a duplicate is only reported for the account it was actually seeded into.
class InMemoryTradeImportRepository implements TradeImportRepository {
  InMemoryTradeImportRepository({
    List<TradeRecord> seed = const <TradeRecord>[],
    String seedAccount = 'default',
  }) {
    for (final TradeRecord r in seed) {
      _byKey[_key(seedAccount, r.externalId)] = r;
    }
  }

  final Map<String, TradeRecord> _byKey = <String, TradeRecord>{};

  static String _key(String accountId, String externalId) =>
      '$accountId::$externalId';

  /// Everything this repository holds, for assertions.
  List<TradeRecord> get records => List<TradeRecord>.unmodifiable(_byKey.values);

  @override
  Future<Set<String>> existingExternalIds(String accountId) async => _byKey.keys
      .where((String k) => k.startsWith('$accountId::'))
      .map((String k) => k.substring(k.indexOf('::') + 2))
      .toSet();

  @override
  Future<int> saveTrades(
    String accountId,
    List<TradeRecord> records, {
    DuplicateStrategy strategy = DuplicateStrategy.skipExisting,
  }) async {
    int written = 0;
    for (final TradeRecord r in records) {
      final String key = _key(accountId, r.externalId);
      final bool exists = _byKey.containsKey(key);
      if (exists && strategy == DuplicateStrategy.fail) {
        throw TradeImportException.of(
          ImportIssueCode.duplicateTradeIdInAccount,
          'This history contains trades that are already in the account. '
          'Nothing was imported.',
        );
      }
      if (exists && strategy == DuplicateStrategy.skipExisting) continue;
      _byKey[key] = r;
      written++;
    }
    return written;
  }
}