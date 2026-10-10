import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../domain/pattern_row.dart';
import 'pattern_repository.dart';

/// Live `v_patterns` reader.
///
/// Two independent defences, because the second alone is not enough:
///
///   1. **RLS on `trades`** (`auth.uid() = user_id`, migration 0002) is the real
///      boundary. Postgres does *not* apply a base table's policies to a view by
///      default — a plain view runs with its owner's privileges — so migration 0006
///      sets `security_invoker = true` on `v_patterns` to make the policies bite.
///   2. **The `user_id` filter below**, read from the live session rather than from
///      any argument. It is defence in depth, not the mechanism: even if the view
///      were misconfigured, the query can only ever ask for the signed-in user's
///      own rows.
///
/// No method here accepts a user id, and the value used comes from
/// `auth.currentUser` — so identity is the session's, never a widget's.
/// The service-role key is never involved: this path uses the anon/publishable key
/// and is therefore subject to RLS exactly as any other client request is.
class SupabasePatternRepository implements PatternRepository {
  SupabasePatternRepository([SupabaseService? service])
      : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  SupabaseClient get _client => _service.client;

  @override
  Future<List<PatternRow>> fetchPatterns() async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      // No session means no honest way to scope the read. Returning empty here
      // would render as "no patterns", which would be a false statement about a
      // journal we simply have not been authorised to see.
      throw const PatternDataException('No signed-in user for the pattern read.');
    }

    final List<Map<String, dynamic>> rows = await (_client
        .from('v_patterns')
        .select()
        .eq('user_id', userId)
        .order('n', ascending: false))
        .timeout(SupabaseService.networkTimeout);

    return rows.map(_toRow).toList(growable: false);
  }

  /// Maps one view row, converting a contract break into [PatternDataException].
  ///
  /// A malformed row is deliberately fatal for the read rather than skipped: a
  /// partial pattern set would quietly understate the trader's sample size, and a
  /// leak detector fed half a journal would draw conclusions from the difference.
  static PatternRow _toRow(Map<String, dynamic> json) {
    try {
      return PatternRow.fromJson(json);
    } on FormatException catch (e) {
      throw PatternDataException(e.message);
    }
  }
}