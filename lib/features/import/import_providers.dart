import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/services.dart';
import 'domain/import_issue.dart';
import 'data/csv_trade_parser.dart';
import 'data/html_trade_parser.dart';
import 'data/supabase_trade_import_repository.dart';
import 'data/trade_file_parser.dart';
import 'data/trade_import_repository.dart';
import 'data/trade_parser_registry.dart';
import 'trade_import_service.dart';

/// Parser registry for the app.
///
/// Adding a format is a one-line change here; no screen or service needs to know about it.
final Provider<TradeParserRegistry> tradeParserRegistryProvider =
    Provider<TradeParserRegistry>((Ref ref) {
  return TradeParserRegistry(
    parsers: <TradeFileParser>[const CsvTradeParser(), const HtmlTradeParser()],
  );
});

/// Persistence boundary, mock-first.
///
/// Mock mode writes to memory so the whole import flow is exercisable with no Supabase project;
/// live mode writes to the `trades` table.
final Provider<TradeImportRepository> tradeImportRepositoryProvider =
    Provider<TradeImportRepository>((Ref ref) {
  return Services.instance.isMock
      ? InMemoryTradeImportRepository()
      : SupabaseTradeImportRepository();
});

/// The one object the UI is allowed to talk to.
final Provider<TradeImportService> tradeImportServiceProvider =
    Provider<TradeImportService>((Ref ref) {
  return TradeImportService(
    registry: ref.watch(tradeParserRegistryProvider),
    repository: ref.watch(tradeImportRepositoryProvider),
  );
});

/// Runs an import and reports progress without ever surfacing a raw parser error.
///
/// Exposed as a notifier so a screen can show a spinner and a trader-safe message, and cannot
/// accidentally reach for `CsvToListConverter` itself.
class TradeImportController extends StateNotifier<TradeImportStatus> {
  TradeImportController(this._service) : super(const TradeImportStatus.idle());

  final TradeImportService _service;

  Future<void> importFile(
    ImportSource source, {
    required String accountId,
    DuplicateStrategy strategy = DuplicateStrategy.skipExisting,
  }) async {
    state = const TradeImportStatus.running();
    try {
      final TradeImportResult result = await _service.importFile(
        source,
        accountId: accountId,
        strategy: strategy,
      );
      state = TradeImportStatus.done(result);
    } on TradeImportException catch (e) {
      // Technical detail stays on the exception for diagnostics; the UI only ever reads
      // `message`, which is why nothing raw is logged or rendered here.
      state = TradeImportStatus.failed(e.message);
    } catch (_) {
      // A non-TradeImportException means a bug, not a bad file. The trader still gets copy
      // they can act on rather than a stack trace.
      state = const TradeImportStatus.failed(
        'That file could not be imported. Try exporting it again.',
      );
    }
  }
}

final StateNotifierProvider<TradeImportController, TradeImportStatus>
    tradeImportControllerProvider =
    StateNotifierProvider<TradeImportController, TradeImportStatus>(
  (Ref ref) => TradeImportController(ref.watch(tradeImportServiceProvider)),
);

/// UI-facing import state. Domain only — no CSV/HTML types appear here.
class TradeImportStatus {
  const TradeImportStatus({
    this.result,
    this.message,
    this.busy = false,
    this.failed = false,
  });

  const TradeImportStatus.idle()
      : result = null,
        message = null,
        busy = false,
        failed = false;

  const TradeImportStatus.running()
      : result = null,
        message = null,
        busy = true,
        failed = false;

  const TradeImportStatus.done(TradeImportResult this.result)
      : message = null,
        busy = false,
        failed = false;

  const TradeImportStatus.failed(String this.message)
      : result = null,
        busy = false,
        failed = true;

  final TradeImportResult? result;

  /// Trader-safe copy. Never a parser exception.
  final String? message;

  final bool busy;
  final bool failed;

  bool get isIdle => result == null && !busy && !failed;
}