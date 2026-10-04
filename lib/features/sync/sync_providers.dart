import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_config.dart';
import '../import/import_providers.dart';
import 'data/metaapi_trade_sync_source.dart';
import 'data/mock_trade_sync_source.dart';
import 'data/supabase_trade_sync_cursor_repository.dart';
import 'data/trade_sync_cursor_repository.dart';
import 'domain/trade_sync_source.dart';
import 'trade_sync_service.dart';

/// Provider seam for the app.
///
/// Mock mode (no `METAAPI_TOKEN`) uses the deterministic offline source, so sync is fully
/// exercisable — and testable — without credentials.
final Provider<TradeSyncSource> tradeSyncSourceProvider =
    Provider<TradeSyncSource>((Ref ref) {
  if (AppConfig.useMock || AppConfig.metaApiToken.isEmpty) {
    return MockTradeSyncSource();
  }
  return MetaApiTradeSyncSource(token: AppConfig.metaApiToken);
});

/// Cursor store. Mock mode keeps watermarks in memory.
final Provider<TradeSyncCursorRepository> tradeSyncCursorRepositoryProvider =
    Provider<TradeSyncCursorRepository>((Ref ref) {
  return AppConfig.useMock
      ? InMemoryTradeSyncCursorRepository()
      : SupabaseTradeSyncCursorRepository();
});

/// The service the UI is allowed to call.
final Provider<TradeSyncService> tradeSyncServiceProvider =
    Provider<TradeSyncService>((Ref ref) {
  return TradeSyncService(
    source: ref.watch(tradeSyncSourceProvider),
    // The SAME repository Task 2.1 wrote: one place that owns trade rows.
    trades: ref.watch(tradeImportRepositoryProvider),
    cursors: ref.watch(tradeSyncCursorRepositoryProvider),
  );
});