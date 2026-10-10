import '../../../../core/services/supabase_service.dart';
import '../domain/import_issue.dart';
import '../domain/trade_record.dart';
import 'trade_import_repository.dart';

/// Supabase persistence for normalized imports.
///
/// The only place in the importer that knows Supabase. It writes [TradeRecord]s to the same
/// `trades` table the journal already reads and relies on the existing
/// `unique (user_id, external_id)` constraint as the final guard against duplicates.
class SupabaseTradeImportRepository implements TradeImportRepository {
  SupabaseTradeImportRepository([SupabaseService? service])
      : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  @override
  Future<Set<String>> existingExternalIds(String accountId) async {
    // Built per branch so the Postgrest builder's generic type is never named.
    final List<Map<String, dynamic>> rows = await (_service.client
        .from('trades')
        .select('external_id')
        .eq('account_id', accountId))
        .timeout(SupabaseService.networkTimeout);
    return rows
        .map((Map<String, dynamic> r) => r['external_id'] as String?)
        .whereType<String>()
        .toSet();
  }

  @override
  Future<int> saveTrades(
    String accountId,
    List<TradeRecord> records, {
    DuplicateStrategy strategy = DuplicateStrategy.skipExisting,
  }) async {
    if (records.isEmpty) return 0;
    if (strategy == DuplicateStrategy.fail) {
      throw TradeImportException.of(
        ImportIssueCode.duplicateTradeIdInAccount,
        'This history contains trades that are already in the account. '
        'Nothing was imported.',
      );
    }

    final List<Map<String, dynamic>> rows = records
        .map((TradeRecord r) => <String, dynamic>{
              ...r.toPersistenceRow(),
              'account_id': accountId,
            },)
        .toList();

    // Conflict target is (account_id, external_id): migration 0005 corrected the original
    // (user_id, external_id), which collided when one trader held two broker accounts that
    // both used the same deal id. This also gives the skip/replace decision a database-level
    // guarantee, so a race between two imports cannot produce two rows. `user_id` is NOT NULL
    // and is filled by RLS/PostgREST, so it is deliberately absent from these rows.
    await _service.client
        .from('trades')
        .upsert(rows, onConflict: 'account_id,external_id')
        .timeout(SupabaseService.networkTimeout);
    return rows.length;
  }
}