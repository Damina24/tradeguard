import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_config.dart';

/// Owns the Supabase client for the whole app.
///
/// The app must boot with no backend configured at all (see [AppConfig.useMock]), so nothing in
/// here may throw while `SUPABASE_URL` is empty — the mock repositories are used instead.
class SupabaseService {
  SupabaseService._();

  static final SupabaseService instance = SupabaseService._();

  SupabaseClient? _client;
  bool _initialized = false;

  /// True when real credentials were supplied at build time.
  bool get isConfigured => !AppConfig.useMock;

  /// True once [init] has completed successfully.
  bool get isReady => _initialized && _client != null;

  SupabaseClient get client {
    final SupabaseClient? c = _client;
    if (c == null) {
      throw StateError(
        'Supabase is not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY, or leave '
        'SUPABASE_URL empty to run in mock mode.',
      );
    }
    return c;
  }

  /// Idempotent, and a no-op in mock mode so [main] can await it unconditionally.
  Future<void> init() async {
    if (_initialized || !isConfigured) return;
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    _client = Supabase.instance.client;
    _initialized = true;
  }
}
