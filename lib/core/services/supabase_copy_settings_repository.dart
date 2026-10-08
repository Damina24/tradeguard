import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/copy_settings.dart';
import 'copy_settings_repository.dart';
import 'supabase_service.dart';

/// The `copy_settings` row, read and written as the signed-in trader.
///
/// Read and write are both own-row only — RLS `own copy settings`
/// (`auth.uid() = user_id` on USING and WITH CHECK, migration 0009) decides
/// the scope; the explicit `user_id` on the upsert is simply what the primary
/// key requires. The Edge Function reads the very same row under the service
/// role, so what this class saves is exactly what `evaluateAccount` will
/// judge a request against: there is no client-side copy of the guardrails
/// that could disagree with the server's.
class SupabaseCopySettingsRepository implements CopySettingsRepository {
  SupabaseCopySettingsRepository([SupabaseService? service])
      : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  SupabaseClient get _client => _service.client;

  @override
  Future<CopySettings> fetchCopySettings() async {
    final List<Map<String, dynamic>> rows = await (_client
        .from('copy_settings')
        .select('live_consent,kill_switch,max_lots,max_concurrent_follows')
        .limit(1));

    // Absent row == defaults: the same fallback index.ts applies, so a trader
    // who has never saved a setting sees the same quartet on both sides.
    if (rows.isEmpty) return CopySettings.defaults;
    return CopySettings.fromJson(rows.first);
  }

  @override
  Future<void> saveCopySettings(CopySettings settings) async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      // Without a session `auth.uid()` is null and the RLS `with check` can
      // never hold, so the upsert would fail with a raw Postgres error. Fail
      // with our own instead — the notifier turns any throw into one generic
      // "couldn't save" line, never server text.
      throw StateError('copy_settings: no signed-in user');
    }

    await _client.from('copy_settings').upsert(
      <String, dynamic>{
        'user_id': userId,
        ...settings.toJson(),
        // `updated_at` is set by the writer — there is no trigger (same
        // convention as prices_cache.updated_at).
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id',
    );
  }
}
