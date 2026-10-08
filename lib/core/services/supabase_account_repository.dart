import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/account.dart';
import 'account_repository.dart';
import 'supabase_service.dart';

/// Live repositories backed by Supabase/Postgres.
///
/// `broker_accounts` holds the static prop-firm rules; the moving numbers (equity, balance, daily
/// P&L, peak equity) live in `equity_snapshots`, written by the `guard-check` Edge Function. The
/// two are merged here so the rest of the app sees one flat [TradingAccount].
class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository([SupabaseService? service])
      : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  SupabaseClient get _client => _service.client;

  @override
  Future<List<TradingAccount>> fetchAccounts() async {
    final List<Map<String, dynamic>> rows = await (_client
            .from('broker_accounts')
            .select()
            .eq('is_active', true)
            .order('created_at', ascending: true));
    final Map<String, AccountSnapshot> snaps = await _latestSnapshots();
    return rows
        .map(
          (Map<String, dynamic> r) =>
              _merge(r, snaps[r['id'] as String?]),
        )
        .toList();
  }

  @override
  Future<AccountSnapshot> fetchSnapshot(String accountId) async {
    final List<Map<String, dynamic>> rows = await (_client
        .from('equity_snapshots')
        .select()
        .eq('account_id', accountId)
        .order('created_at', ascending: false)
        .limit(1));
    if (rows.isEmpty) {
      // No snapshot yet — the guard renders this as STALE rather than inventing numbers.
      return AccountSnapshot(
        equity: 0,
        balance: 0,
        dailyPnl: 0,
        peakEquity: 0,
        asOf: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
    final Map<String, dynamic> r = rows.first;
    return AccountSnapshot(
      equity: (r['equity'] as num?)?.toDouble() ?? 0,
      balance: (r['balance'] as num?)?.toDouble() ?? 0,
      dailyPnl: (r['daily_pnl'] as num?)?.toDouble() ?? 0,
      peakEquity: (r['peak_equity'] as num?)?.toDouble() ?? 0,
      asOf: DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  @override
  Future<TradingAccount> createAccount(TradingAccount account) async {
    final Map<String, dynamic> row = await (_client
        .from('broker_accounts')
        .insert(_toRow(account))
        .select()
        .single());
    return _merge(row, AccountSnapshot.fromAccount(account));
  }

  @override
  Future<void> deleteAccount(String accountId) async {
    await _client.from('broker_accounts').delete().eq('id', accountId);
  }

  @override
  Future<void> setEquityGuardEnabled(String accountId, bool enabled) async {
    await _client
        .from('broker_accounts')
        .update(<String, dynamic>{'equity_guard_enabled': enabled})
        .eq('id', accountId);
  }

  @override
  Future<void> setCopyEnabled(String accountId, bool enabled) async {
    // RLS `own accounts` scopes the update to the caller's row, so a foreign
    // id matches zero rows rather than touching somebody else's permission.
    await _client
        .from('broker_accounts')
        .update(<String, dynamic>{'copy_enabled': enabled})
        .eq('id', accountId);
  }

  /// Latest snapshot per account. `equity_snapshots` is append-only and written once a minute, so
  /// descending order means the first row seen for an account is its newest one.
  Future<Map<String, AccountSnapshot>> _latestSnapshots() async {
    final List<Map<String, dynamic>> rows = await (_client
        .from('equity_snapshots')
        .select()
        .order('created_at', ascending: false)
        .limit(2000));
    final Map<String, AccountSnapshot> out = <String, AccountSnapshot>{};
    for (final Map<String, dynamic> r in rows) {
      final String id = r['account_id'] as String;
      if (out.containsKey(id)) continue;
      out[id] = AccountSnapshot(
        equity: (r['equity'] as num?)?.toDouble() ?? 0,
        balance: (r['balance'] as num?)?.toDouble() ?? 0,
        dailyPnl: (r['daily_pnl'] as num?)?.toDouble() ?? 0,
        peakEquity: (r['peak_equity'] as num?)?.toDouble() ?? 0,
        asOf:
            DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
      );
    }
    return out;
  }

  /// Only columns that actually exist on `broker_accounts`. Live numbers are never written here.
  static Map<String, dynamic> _toRow(TradingAccount a) => <String, dynamic>{
        'platform': a.platform,
        'metaapi_account_id': a.metaapiAccountId,
        'nickname': a.nickname,
        'prop_firm': a.propFirm,
        'phase': a.phase.name,
        'currency': a.currency,
        'initial_balance': a.initialBalance,
        'profit_target': a.profitTarget,
        'daily_loss_limit': a.dailyLossLimit,
        'max_drawdown': a.maxDrawdown,
        'drawdown_type': a.drawdownType.name,
        'equity_guard_enabled': a.equityGuardEnabled,
        'copy_enabled': a.copyEnabled,
        'is_active': true,
      };

  static TradingAccount _merge(
    Map<String, dynamic> row,
    AccountSnapshot? snap,
  ) =>
      TradingAccount.fromJson(<String, dynamic>{
        ...row,
        'equity': snap?.equity,
        'balance': snap?.balance,
        'daily_pnl': snap?.dailyPnl,
        'peak_equity': snap?.peakEquity,
      });
}
