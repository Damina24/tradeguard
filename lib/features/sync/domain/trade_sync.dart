import 'dart:math' as math;

import '../../import/domain/import_issue.dart';
import '../../import/domain/trade_record.dart';
import '../data/trade_sync_mapper.dart';

/// How far back a sync looks when it has no cursor yet.
///
/// A brand-new account is back-filled from this far, then the cursor takes over. Bounded so
/// the very first run cannot pull an unbounded history and blow the provider's rate limit.
const Duration kInitialSyncWindow = Duration(days: 30);

/// Upper bound on any single sync window.
///
/// Guards two failure modes: an unbounded first run, and a cursor that silently resets (after a
/// manual wipe, say) and re-reads years of history.
const int kMaxWindowDays = 90;

/// How far before the cursor we re-read.
///
/// Brokers close a deal in stages — commission or swap can be booked after the fact, and a
/// deal moves from open to closed. A pure `> lastSyncedAt` window would miss those updates, so
/// every run deliberately overlaps and relies on `external_id` dedupe to make the re-read
/// idempotent. Timestamps narrow the window; the id is what guarantees correctness.
const Duration kSyncOverlap = Duration(hours: 6);

/// Hard ceiling on pages fetched per account, so a provider that always answers `hasMore`
/// cannot spin forever or exhaust the shared rate limit.
const int kMaxPagesPerSync = 20;

/// Where a successful sync got to, per account.
///
/// This is the cursor. `external_id` is the *identity* guarantee and `lastSyncedAt` is only a
/// narrowing optimization: a trade is identified by its provider id, never by its timestamp —
/// two trades can share a millisecond, and a broker can restate a close time.
class TradeSyncCursor {
  const TradeSyncCursor({
    required this.accountId,
    this.lastSyncedAt,
    this.lastExternalId,
    this.lastRunAt,
    this.consecutiveFailures = 0,
  });

  /// Our account id. Always scoped — a cursor never spans accounts.
  final String accountId;

  /// Watermark for the next window.
  final DateTime? lastSyncedAt;

  /// Last provider id stored, kept for diagnostics and ordering only.
  final String? lastExternalId;

  /// When the last run completed, successful or not.
  final DateTime? lastRunAt;

  /// Consecutive failures. Drives backoff so a dead account is not retried every 5 minutes.
  final int consecutiveFailures;

  bool get isFirstRun => lastSyncedAt == null;

  /// Start of the window the next run should read.
  ///
  /// First run: [kInitialSyncWindow] back. Later: the watermark minus [kSyncOverlap], clamped so
  /// the window never exceeds [kMaxWindowDays].
  DateTime windowStart(DateTime now) {
    final DateTime? watermark = lastSyncedAt;
    if (watermark == null) return now.subtract(kInitialSyncWindow);
    final DateTime start = watermark.subtract(kSyncOverlap);
    final DateTime floor = now.subtract(const Duration(days: kMaxWindowDays));
    return start.isBefore(floor) ? floor : start;
  }

  /// How long to wait before the next attempt, given consecutive failures.
  ///
  /// Exponential backoff capped at an hour, so an account whose provider credentials died
  /// stops consuming the shared allowance instead of failing every five minutes.
  Duration backoff() {
    if (consecutiveFailures <= 0) return Duration.zero;
    const int maxMinutes = 60;
    final int minutes =
        math.min(maxMinutes, 1 << math.min(consecutiveFailures - 1, 6));
    return Duration(minutes: minutes);
  }

  TradeSyncCursor copyWith({
    DateTime? lastSyncedAt,
    String? lastExternalId,
    DateTime? lastRunAt,
    int? consecutiveFailures,
  }) =>
      TradeSyncCursor(
        accountId: accountId,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastExternalId: lastExternalId ?? this.lastExternalId,
        lastRunAt: lastRunAt ?? this.lastRunAt,
        consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      );

  @override
  bool operator ==(Object other) =>
      other is TradeSyncCursor &&
      other.accountId == accountId &&
      other.lastSyncedAt == lastSyncedAt &&
      other.lastExternalId == lastExternalId &&
      other.consecutiveFailures == consecutiveFailures;

  @override
  int get hashCode => Object.hash(
        accountId,
        lastSyncedAt,
        lastExternalId,
        consecutiveFailures,
      );

  @override
  String toString() =>
      'TradeSyncCursor($accountId, since: $lastSyncedAt, fails: '
      '$consecutiveFailures)';
}
/// Outcome of one account's sync, in domain terms.
class TradeSyncOutcome {
  const TradeSyncOutcome({
    required this.accountId,
    required this.providerAccountId,
    required this.fetched,
    required this.imported,
    required this.updated,
    required this.skipped,
    required this.issues,
    required this.pages,
    required this.windowStart,
  });

  final String accountId;

  /// Opaque provider account reference. Safe to log; it is not a credential.
  final String providerAccountId;

  /// Records the provider returned.
  final int fetched;

  /// New trades written.
  final int imported;

  /// Existing trades restated (a broker updated a commission, say).
  final int updated;

  /// Records dropped: unmappable rows, and rows already stored.
  final int skipped;

  final List<ImportIssue> issues;

  final int pages;

  /// Window this run covered.
  final DateTime windowStart;

  bool get isEmpty => imported == 0 && updated == 0;

  bool get isPartial => issues.isNotEmpty;

  Map<String, dynamic> toSummary() => <String, dynamic>{
        'account_id': accountId,
        'fetched': fetched,
        'imported': imported,
        'updated': updated,
        'skipped': skipped,
        'pages': pages,
      };

  @override
  String toString() =>
      'TradeSyncOutcome($accountId: fetched $fetched, imported $imported, '
      'updated $updated, skipped $skipped)';
}

/// Maps one page of provider deals into canonical [TradeRecord]s.
///
/// A separate step from the service so the mapping rules are unit-testable with no provider,
/// no repository and no clock.
class TradeSyncBatchMapper {
  const TradeSyncBatchMapper([this.mapper = const TradeSyncMapper()]);

  final TradeSyncMapper mapper;

  /// Converts a page, dropping unmappable rows and keeping the first of any duplicate id.
  ///
  /// Duplicate ids WITHIN one response are collapsed here (first wins) so the service sees a
  /// clean list; duplicates ACROSS runs are the repository's job.
  ({List<TradeRecord> records, List<ImportIssue> issues}) mapPage(
    List<Map<String, dynamic>> deals,
  ) {
    final List<ImportIssue> issues = <ImportIssue>[];
    final Set<String> seen = <String>{};
    final List<TradeRecord> records = <TradeRecord>[];

    for (final Map<String, dynamic> deal in deals) {
      final TradeRecord? record = mapper.map(deal, issues: issues);
      if (record == null) continue;
      if (seen.add(record.externalId)) {
        records.add(record);
      } else {
        issues.add(ImportIssue(
          ImportIssueCode.duplicateTradeId,
          field: 'trade ID',
          message: 'Trade ${record.externalId} was returned twice by your '
              'broker; only the first was kept.',
        ),);
      }
    }
    return (records: records, issues: issues);
  }
}