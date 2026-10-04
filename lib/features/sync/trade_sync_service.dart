import '../import/data/trade_import_repository.dart';
import '../import/domain/import_issue.dart';
import '../import/domain/trade_record.dart';
import 'data/trade_sync_cursor_repository.dart';
import 'domain/trade_sync.dart';
import 'domain/trade_sync_source.dart';

/// An account eligible for synchronization.
///
/// [providerAccountId] is the broker-side reference we already persist (MetaAPI's account id).
/// It is an identifier, not a credential; the provider token never travels with it.
class SyncableAccount {
  const SyncableAccount({
    required this.accountId,
    required this.userId,
    required this.providerAccountId,
    this.enabled = true,
  });

  /// Our id, and the tenant boundary for everything this sync writes.
  final String accountId;

  final String userId;

  /// Provider-side account reference; see [isConfigured].
  final String? providerAccountId;

  /// Whether the owner wants this account synced.
  final bool enabled;

  bool get isConfigured => (providerAccountId ?? '').isNotEmpty;
}

/// Drives `sync-trades`: fetch → map → dedupe → persist → advance cursor.
///
/// The only class that knows all three collaborators. It holds no credentials, opens no socket
/// and writes no SQL, so the interesting behaviour (windowing, paging, idempotency, backoff) is
/// testable with three fakes.
///
/// Idempotency contract: running this twice against unchanged provider data writes nothing the
/// second time. That is guaranteed by `external_id` — the broker's own id — combined with the
/// overlapping window and `DuplicateStrategy.replaceExisting`, never by timestamps alone.
class TradeSyncService {
  const TradeSyncService({
    required TradeSyncSource source,
    required TradeImportRepository trades,
    required TradeSyncCursorRepository cursors,
    DateTime Function()? clock,
    this.batchMapper = const TradeSyncBatchMapper(),
    this.pageLimit = 100,
  })  : _source = source,
        _trades = trades,
        _cursors = cursors,
        _now = clock ?? DateTime.now;

  final TradeSyncSource _source;
  final TradeImportRepository _trades;
  final TradeSyncCursorRepository _cursors;
  final DateTime Function() _now;
  final TradeSyncBatchMapper batchMapper;

  /// Provider page size requested per fetch.
  final int pageLimit;

  /// Syncs one account.
  ///
  /// Throws [TradeSyncException] when the account could not be synced; returns an outcome with
  /// `imported == 0` for a legitimate empty window. The two are deliberately different: "no
  /// new trades" is a normal quiet outcome and must never look like an error.
  Future<TradeSyncOutcome> syncAccount(SyncableAccount account) async {
    final DateTime now = _now();

    if (!account.isConfigured) {
      throw const TradeSyncException(
        TradeSyncFailure.notConfigured,
        'This account is not connected to a broker yet.',
      );
    }

    final TradeSyncCursor stored = await _cursors.read(account.accountId) ??
        TradeSyncCursor(accountId: account.accountId);

    // Backoff: a repeatedly failing account must not keep spending the shared provider
    // allowance on every scheduled run.
    final DateTime? lastRun = stored.lastRunAt;
    if (lastRun != null && now.difference(lastRun) < stored.backoff()) {
      throw const TradeSyncException(
        TradeSyncFailure.rateLimited,
        'This account is waiting before the next broker sync.',
      );
    }

    final DateTime windowStart = stored.windowStart(now);
    final List<TradeRecord> all = <TradeRecord>[];
    final List<ImportIssue> issues = <ImportIssue>[];
    // Counts what the PROVIDER returned, separately from what we could map: an operator
    // reading the logs needs to see "400 fetched, 397 stored", not "397 fetched".
    int fetched = 0;
    String? cursorToken;
    bool hasMore = true;
    int pages = 0;

    while (hasMore && pages < kMaxPagesPerSync) {
      final TradeSyncPage page;
      try {
        page = await _source.fetchTrades(
          providerAccountId: account.providerAccountId!,
          since: windowStart,
          cursor: cursorToken,
          limit: pageLimit,
        );
      } on TradeSyncException {
        await _recordFailure(account, stored, now);
        rethrow;
      } catch (e) {
        // A source that throws something raw must not escape to the UI.
        await _recordFailure(account, stored, now);
        throw TradeSyncException(
          TradeSyncFailure.network,
          'Could not reach your broker to sync trades.',
          detail: e.toString(),
        );
      }

      final ({List<TradeRecord> records, List<ImportIssue> issues}) mapped =
          batchMapper.mapPage(page.deals);
      all.addAll(mapped.records);
      issues.addAll(mapped.issues);
      fetched += page.deals.length;

      pages++;
      hasMore = page.hasMore && page.nextCursor != null;
      cursorToken = page.nextCursor ?? cursorToken;
      if (page.deals.isEmpty) break;
    }

    return _persist(
        account, all, issues, pages, windowStart, now, stored, fetched,);
  }

  /// Syncs many accounts, isolating failures.
  ///
  /// One dead account must not stop the rest, which is what makes a partial cron run useful
  /// rather than all-or-nothing.
  Future<List<TradeSyncOutcome>> syncAccounts(
    List<SyncableAccount> accounts,
  ) async {
    final List<TradeSyncOutcome> out = <TradeSyncOutcome>[];
    for (final SyncableAccount a in accounts) {
      if (!a.enabled) continue;
      try {
        out.add(await syncAccount(a));
      } on TradeSyncException {
        // Already recorded against the cursor; the run summary reports the shortfall.
        continue;
      }
    }
    return out;
  }
/// Writes through the Task 2.1 repository, then advances the cursor.
  ///
  /// `replaceExisting` rather than `skipExisting`: a broker restating a commission or a close
  /// price must update the stored row. It cannot create a duplicate, because the unique key is
  /// still `external_id`.
  Future<TradeSyncOutcome> _persist(
    SyncableAccount account,
    List<TradeRecord> records,
    List<ImportIssue> issues,
    int pages,
    DateTime windowStart,
    DateTime now,
    TradeSyncCursor stored,
    int fetched,
  ) async {
    if (records.isEmpty) {
      // An empty window is a success: advance the watermark so we do not re-scan the same
      // quiet stretch every five minutes, and reset the failure counter.
      await _cursors.write(
        stored.copyWith(
          lastSyncedAt: now,
          lastRunAt: now,
          consecutiveFailures: 0,
        ),
      );
      return TradeSyncOutcome(
        accountId: account.accountId,
        providerAccountId: account.providerAccountId ?? '',
        fetched: fetched,
        imported: 0,
        updated: 0,
        skipped: issues.length,
        issues: issues,
        pages: pages,
        windowStart: windowStart,
      );
    }

    final Set<String> existing =
        await _trades.existingExternalIds(account.accountId);
    final int newCount = records
        .where((TradeRecord r) => !existing.contains(r.externalId))
        .length;

    final int written;
    try {
      written = await _trades.saveTrades(
        account.accountId,
        records,
        strategy: DuplicateStrategy.replaceExisting,
      );
    } on TradeImportException catch (e) {
      // A duplicate-policy refusal is not a cursor problem; do NOT advance, so the run retries.
      await _recordFailure(account, stored, now);
      throw TradeSyncException(
        TradeSyncFailure.persistenceFailed,
        e.message,
        detail: e.detail,
      );
    } catch (e) {
      await _recordFailure(account, stored, now);
      throw TradeSyncException(
        TradeSyncFailure.persistenceFailed,
        'Your trades could not be saved. Try again shortly.',
        detail: e.toString(),
      );
    }

    await _cursors.write(
      stored.copyWith(
        lastSyncedAt: now,
        lastExternalId: records.last.externalId,
        lastRunAt: now,
        consecutiveFailures: 0,
      ),
    );

    return TradeSyncOutcome(
      accountId: account.accountId,
      providerAccountId: account.providerAccountId ?? '',
      fetched: fetched,
      imported: newCount,
      updated: written - newCount,
      skipped: issues.length,
      issues: issues,
      pages: pages,
      windowStart: windowStart,
    );
  }

  /// Bumps the failure counter without moving the watermark.
  ///
  /// Never advancing `lastSyncedAt` on failure is what makes a retry re-read the same window
  /// instead of skipping trades that arrived during the outage.
  Future<void> _recordFailure(
    SyncableAccount account,
    TradeSyncCursor stored,
    DateTime now,
  ) async {
    await _cursors.write(
      stored.copyWith(
        lastRunAt: now,
        consecutiveFailures: stored.consecutiveFailures + 1,
      ),
    );
  }
}