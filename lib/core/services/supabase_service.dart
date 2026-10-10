import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_config.dart';

/// Owns the Supabase client for the whole app.
///
/// The app must boot with no backend configured at all (see [AppConfig.useMock]), so nothing in
/// here may throw while no Supabase keys were supplied at build time — the mock repositories are
/// used instead.
class SupabaseService {
  SupabaseService._();

  static final SupabaseService instance = SupabaseService._();

  SupabaseClient? _client;
  bool _initialized = false;

  /// True when real credentials were supplied at build time.
  ///
  /// Reads [AppConfig.hasSupabaseConfig] rather than `!AppConfig.useMock`: those
  /// disagree exactly where it matters. A release build that asked for demo mode
  /// (`USE_MOCK=true`) is not "configured", and neither is any build whose URL is
  /// present but whose anon key is missing — initialising with a blank publishable
  /// key would fail later at the first request instead of here.
  bool get isConfigured => AppConfig.hasSupabaseConfig;

  /// True once [init] has completed successfully.
  bool get isReady => _initialized && _client != null;

  SupabaseClient get client {
    final SupabaseClient? c = _client;
    if (c == null) {
      throw StateError(
        'Supabase is not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY, '
        'or build in demo mode with --dart-define=USE_MOCK=true.',
      );
    }
    return c;
  }

  /// Idempotent, and a no-op unless the build carries both halves of the config,
  /// so [main] can await it unconditionally.
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
