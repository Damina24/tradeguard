import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/signal.dart';
import '../../../core/services/supabase_service.dart';
import 'signal_repository.dart';

/// Live `signals` reader.
///
/// Two independent defences, mirroring `SupabasePatternRepository`:
///
///   1. **RLS on `signals`** (policy `"signals read"`, migration 0002) is the
///      real boundary: only authenticated sessions may read, and the table
///      holds operator-posted rows with no per-user scoping to bypass.
///   2. **The session gate below**: with no signed-in user there is no honest
///      way to be scoped by RLS, so this throws rather than returning an
///      empty list that would render as "no signals posted".
///
/// No method here accepts a user id, and the only identity used is
/// `auth.currentUser` — so identity is the session's, never a widget's.
/// The service-role key is never involved: this path uses the
/// anon/publishable key and is therefore subject to RLS exactly as any other
/// client request is.
class SupabaseSignalRepository implements SignalRepository {
  SupabaseSignalRepository([SupabaseService? service])
      : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  SupabaseClient get _client => _service.client;

  @override
  bool get isStubbed => false;

  @override
  Future<List<Signal>> fetchSignals({int limit = 100}) async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      // No session means no honest way to be scoped by RLS. Returning empty
      // here would render as "no signals posted", which would be a false
      // statement about a feed we simply have not been authorised to see.
      throw const SignalDataException('No signed-in user for the signal read.');
    }

    final List<Map<String, dynamic>> rows = await (_client
        .from('signals')
        .select()
        .order('created_at', ascending: false)
        .limit(limit))
        .timeout(SupabaseService.networkTimeout);

    return rows.map(_toSignal).toList(growable: false);
  }

  /// Maps one table row, converting a contract break into
  /// [SignalDataException].
  ///
  /// A malformed row is deliberately fatal for the read rather than skipped:
  /// a partial feed would quietly understate the sample the verified stats
  /// are computed from, and stats drawn from half a feed are the misleading
  /// kind this product must not ship.
  static Signal _toSignal(Map<String, dynamic> json) {
    try {
      return Signal.fromJson(json);
    } on FormatException catch (e) {
      throw SignalDataException(e.message);
    } catch (e) {
      throw SignalDataException('Unusable signal row: $e');
    }
  }
}
