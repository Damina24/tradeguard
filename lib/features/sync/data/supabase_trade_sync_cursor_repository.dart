import '../../../core/services/supabase_service.dart';
import '../domain/trade_sync.dart';
import 'trade_sync_cursor_repository.dart';

/// Persists sync cursors in `trade_sync_cursors` (migration 0005).
///
/// The table is RLS-protected on `user_id`, and every query here filters by account, so the
/// service-role client used by the cron is the only thing that can read across users — and it
/// only ever does so through [listEligible] with an explicit owner.
class SupabaseTradeSyncCursorRepository implements TradeSyncCursorRepository {
  SupabaseTradeSyncCursorRepository([SupabaseService? service])
      : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  @override
  Future<TradeSyncCursor?> read(String accountId) async {
    // deno-lint-ignore no-explicit-any
    final List<Map<String, dynamic>> rows = await (_service.client
        .from('trade_sync_cursors')
        .select('account_id,last_synced_at,last_external_id,last_run_at,'
            'consecutive_failures')
        .eq('account_id', accountId)
        .limit(1));
    if (rows.isEmpty) return null;
    return _toCursor(rows.first);
  }

  @override
  Future<void> write(TradeSyncCursor cursor) async {
    // deno-lint-ignore no-explicit-any
    await (_service.client.from('trade_sync_cursors').upsert(<String, dynamic>{
      'account_id': cursor.accountId,
      'last_synced_at': cursor.lastSyncedAt?.toUtc().toIso8601String(),
      'last_external_id': cursor.lastExternalId,
      'last_run_at': cursor.lastRunAt?.toUtc().toIso8601String(),
      'consecutive_failures': cursor.consecutiveFailures,
    }, onConflict: 'account_id',));
  }

  @override
  Future<List<TradeSyncCursor>> listEligible({String? userId}) async {
    final Map<String, String> filters = <String, String>{};
    if (userId != null) filters['user_id'] = userId;
    // deno-lint-ignore no-explicit-any
    final List<Map<String, dynamic>> rows = await (_service.client
        .from('trade_sync_cursors')
        .select('account_id,last_synced_at,last_external_id,last_run_at,'
            'consecutive_failures')
        .match(filters));
    return rows.map(_toCursor).toList();
  }

  static TradeSyncCursor _toCursor(Map<String, dynamic> row) => TradeSyncCursor(
        accountId: row['account_id'] as String,
        lastSyncedAt: _date(row['last_synced_at']),
        lastExternalId: row['last_external_id'] as String?,
        lastRunAt: _date(row['last_run_at']),
        consecutiveFailures: (row['consecutive_failures'] as num?)?.toInt() ?? 0,
      );

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v as String)?.toUtc();
}