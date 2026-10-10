import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/trade.dart';
import 'supabase_service.dart';
import 'trade_repository.dart';

class SupabaseTradeRepository implements TradeRepository {
  SupabaseTradeRepository([SupabaseService? service])
      : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  SupabaseClient get _client => _service.client;

  @override
  Future<List<Trade>> fetchTrades({String? accountId, int limit = 200}) async {
    // Built per branch so we never have to name the Postgrest builder's generic type.
    final List<Map<String, dynamic>> rows = accountId == null
        ? await (_client
            .from('trades')
            .select()
            .order('close_time', ascending: false)
            .limit(limit))
            .timeout(SupabaseService.networkTimeout)
        : await (_client
            .from('trades')
            .select()
            .eq('account_id', accountId)
            .order('close_time', ascending: false)
            .limit(limit))
            .timeout(SupabaseService.networkTimeout);
    return rows.map(Trade.fromJson).toList();
  }

  @override
  Future<void> updateGrade(String tradeId, String grade) =>
      _patch(tradeId, <String, dynamic>{'grade': grade});

  @override
  Future<void> updateNotes(String tradeId, String notes) =>
      _patch(tradeId, <String, dynamic>{'notes': notes});

  @override
  Future<void> updateScreenshot(String tradeId, String screenshotPath) =>
      _patch(tradeId, <String, dynamic>{'screenshot_url': screenshotPath});

  Future<void> _patch(String tradeId, Map<String, dynamic> values) async {
    await _client
        .from('trades')
        .update(values)
        .eq('id', tradeId)
        .timeout(SupabaseService.networkTimeout);
  }
}
