import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/trade.dart';
import 'package:tradeguard/features/import/data/trade_import_repository.dart';
import 'package:tradeguard/features/import/domain/import_issue.dart';
import 'package:tradeguard/features/import/domain/trade_record.dart';
import 'package:tradeguard/features/sync/data/mock_trade_sync_source.dart';
import 'package:tradeguard/features/sync/data/trade_sync_cursor_repository.dart';
import 'package:tradeguard/features/sync/domain/trade_sync.dart';
import 'package:tradeguard/features/sync/domain/trade_sync_source.dart';
import 'package:tradeguard/features/sync/trade_sync_service.dart';

final DateTime now = DateTime.utc(2026, 4, 20, 12);

/// Everything a test needs to inspect, built fresh so no test sees another's state.
({
  TradeSyncService service,
  MockTradeSyncSource source,
  InMemoryTradeImportRepository trades,
  InMemoryTradeSyncCursorRepository cursors,
}) build({List<TradeSyncCursor>? seedCursors}) {
  final MockTradeSyncSource source = MockTradeSyncSource();
  final InMemoryTradeImportRepository trades = InMemoryTradeImportRepository();
  final InMemoryTradeSyncCursorRepository cursors =
      InMemoryTradeSyncCursorRepository(seedCursors);
  return (
    service: TradeSyncService(
      source: source,
      trades: trades,
      cursors: cursors,
      clock: () => now,
    ),
    source: source,
    trades: trades,
    cursors: cursors,
  );
}

const SyncableAccount acc = SyncableAccount(
  accountId: 'acc-1',
  userId: 'user-1',
  providerAccountId: 'meta-1',
);

SyncableAccount account({
  String id = 'acc-1',
  String? providerId = 'meta-1',
  bool enabled = true,
}) =>
    SyncableAccount(
      accountId: id,
      userId: 'user-1',
      providerAccountId: providerId,
      enabled: enabled,
    );

Map<String, dynamic> deal({
  String ticket = '900001',
  String symbol = 'XAUUSD',
  String type = 'buy',
  Object volume = 0.5,
  Object profit = 312,
}) =>
    <String, dynamic>{
      'ticket': ticket,
      'openTime': '2026-04-15T08:30:00Z',
      'closeTime': '2026-04-15T12:00:00Z',
      'type': type,
      'volume': volume,
      'symbol': symbol,
      'openPrice': 2345.10,
      'closePrice': 2351.40,
      'profit': profit,
      'commission': -3.50,
      'swap': -0.70,
      'currency': 'USD',
    };

void main() {
  group('successful sync', () {
    test('imports the provider history through the Task 2.1 repository',
        () async {
      final s = build();
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);

      expect(outcome.imported, 3);
      expect(outcome.updated, 0);
      expect(outcome.fetched, 3);
      expect(outcome.issues, isEmpty);

      // Written as canonical TradeRecords, not provider maps.
      expect(s.trades.records.length, 3);
      expect(
        s.trades.records.every((TradeRecord r) => r.externalId.isNotEmpty),
        isTrue,
      );
    });

    test('normalizes into the canonical TradeRecord', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[deal()]);
      await s.service.syncAccount(acc);

      final TradeRecord saved = s.trades.records.single;
      expect(saved.externalId, '900001');
      expect(saved.symbol, 'XAUUSD');
      expect(saved.direction, TradeDirection.long);
      expect(saved.volumeLots, 0.5);
      expect(saved.entryPrice, 2345.10);
      expect(saved.closeTime, DateTime.utc(2026, 4, 15, 12));
      // Net of commission and swap, matching TradeRecord.netPnl.
      expect(saved.netPnl, closeTo(307.80, 0.0001));
    });

    test('maps sell trades to short', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[deal(type: 'sell')]);
      await s.service.syncAccount(acc);
      expect(s.trades.records.single.direction, TradeDirection.short);
    });

    test('handles multiple symbols', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[
        deal(ticket: '1', symbol: 'XAUUSD'),
        deal(ticket: '2', symbol: 'EURUSD'),
        deal(ticket: '3', symbol: 'GBPJPY'),
      ]);
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);
      expect(outcome.imported, 3);
      expect(
        s.trades.records.map((TradeRecord r) => r.symbol).toSet(),
        <String>{'XAUUSD', 'EURUSD', 'GBPJPY'},
      );
    });

    test('advances the cursor on success', () async {
      final s = build();
      await s.service.syncAccount(acc);
      final TradeSyncCursor cursor = (await s.cursors.read('acc-1'))!;
      expect(cursor.lastSyncedAt, now);
      expect(cursor.lastExternalId, isNotNull);
      expect(cursor.consecutiveFailures, 0);
      expect(cursor.isFirstRun, isFalse);
    });
  });

  group('empty response', () {
    test('an empty provider response is a quiet success', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[]);
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);

      expect(outcome.imported, 0);
      expect(outcome.fetched, 0);
      expect(outcome.isEmpty, isTrue);
      expect(s.trades.records, isEmpty);
    });

    test('an empty response still advances the cursor', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[]);
      await s.service.syncAccount(acc);
      expect((await s.cursors.read('acc-1'))!.lastSyncedAt, now);
    });
  });
group('idempotency', () {
    test('running the same sync twice creates no duplicates', () async {
      final s = build();
      final TradeSyncOutcome first = await s.service.syncAccount(acc);
      expect(first.imported, 3);

      final TradeSyncOutcome second = await s.service.syncAccount(acc);

      // The core guarantee: unchanged provider data writes nothing new.
      expect(second.imported, 0);
      expect(s.trades.records.length, 3);
    });

    test('a third run is still idempotent', () async {
      final s = build();
      await s.service.syncAccount(acc);
      await s.service.syncAccount(acc);
      final TradeSyncOutcome third = await s.service.syncAccount(acc);
      expect(third.imported, 0);
      expect(s.trades.records.length, 3);
    });

    test('a broker restatement updates instead of duplicating', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[deal(profit: 312)]);
      await s.service.syncAccount(acc);
      expect(s.trades.records.single.profit, 312);

      // The broker restates the same ticket with a new profit.
      s.source.replaceAll(<Map<String, dynamic>>[deal(profit: 500)]);
      final TradeSyncOutcome restated = await s.service.syncAccount(acc);

      expect(restated.imported, 0);
      expect(restated.updated, 1);
      expect(s.trades.records.length, 1);
      expect(s.trades.records.single.profit, 500);
    });

    test('P&L is not double counted on re-run', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[deal(profit: 100)]);
      await s.service.syncAccount(acc);
      await s.service.syncAccount(acc);

      final double net = s.trades.records.fold<double>(
        0,
        (double sum, TradeRecord r) => sum + r.netPnl,
      );
      expect(net, closeTo(95.80, 0.0001));
    });
  });

  group('incremental sync', () {
    test('the first run uses a bounded window', () async {
      final s = build();
      await s.service.syncAccount(acc);

      final DateTime since =
          DateTime.parse(s.source.calls.first['since'] as String);
      expect(now.difference(since).inDays, kInitialSyncWindow.inDays);
    });

    test('a later run only asks for the overlap', () async {
      final s = build();
      await s.service.syncAccount(acc);
      s.source.replaceAll(<Map<String, dynamic>>[]);
      await s.service.syncAccount(acc);

      final DateTime since =
          DateTime.parse(s.source.calls.last['since'] as String);
      // The watermark is `now`; the next run starts 6 hours before it.
      expect(
        now.difference(since),
        greaterThanOrEqualTo(kSyncOverlap - const Duration(minutes: 1)),
      );
      expect(
        now.difference(since),
        lessThanOrEqualTo(kSyncOverlap + const Duration(minutes: 1)),
      );
    });

    test('only newly-added trades are imported', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[deal(ticket: '1')]);
      await s.service.syncAccount(acc);
      expect(s.trades.records.length, 1);

      // The broker adds one more trade.
      s.source.append(deal(ticket: '2'));
      final TradeSyncOutcome second = await s.service.syncAccount(acc);

      expect(second.imported, 1);
      expect(second.updated, 1); // '1' came back in the overlap window
      expect(s.trades.records.length, 2);
    });

    test('the window never exceeds the maximum', () async {
      final s = build(
        seedCursors: <TradeSyncCursor>[
          TradeSyncCursor(
            accountId: 'acc-1',
            lastSyncedAt: DateTime.utc(2000),
          ),
        ],
      );
      await s.service.syncAccount(acc);
      final DateTime since =
          DateTime.parse(s.source.calls.first['since'] as String);
      expect(now.difference(since).inDays, lessThanOrEqualTo(kMaxWindowDays));
    });
  });
group('pagination', () {
    test('follows the provider cursor across pages', () async {
      final s = build();
      s.source.pageSize = 1; // one deal per page
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);

      expect(outcome.pages, 3);
      expect(outcome.fetched, 3);
      expect(outcome.imported, 3);
      expect(s.trades.records.length, 3);
    });

    test('passes the cursor token to the next page', () async {
      final s = build();
      s.source.pageSize = 1;
      await s.service.syncAccount(acc);
      expect(s.source.calls.length, 3);
      expect(s.source.calls[0]['cursor'], isNull);
      expect(s.source.calls[1]['cursor'], isNotNull);
    });

    test('honours the page size', () async {
      final s = build();
      s.source.replaceAll(
        List<Map<String, dynamic>>.generate(10, (int i) => deal(ticket: 't$i')),
      );
      s.source.pageSize = 3;
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);
      // ceil(10 / 3) = 4 pages, and all 10 deals are collected.
      expect(outcome.pages, 4);
      expect(outcome.fetched, 10);
      expect(s.trades.records.length, 10);
    });

    test('a page cap prevents an endless provider loop', () async {
      final s = build();
      // A provider that always claims more work must not spin forever.
      s.source.pageSize = 1;
      s.source.replaceAll(
        List<Map<String, dynamic>>.generate(100, (int i) => deal(ticket: 't$i')),
      );
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);
      expect(outcome.pages, lessThanOrEqualTo(kMaxPagesPerSync));
    });
  });

  group('duplicate handling', () {
    test('duplicate ids in one response collapse to the first', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[
        deal(ticket: 'dup', profit: 100),
        deal(ticket: 'dup', profit: 999),
      ]);
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);

      expect(outcome.imported, 1);
      expect(s.trades.records.length, 1);
      // First wins: the 999 restatement must not overwrite within the same page.
      expect(s.trades.records.single.profit, 100);
      expect(
        outcome.issues.map((ImportIssue i) => i.code),
        contains(ImportIssueCode.duplicateTradeId),
      );
    });

    test('the same external id in two accounts is two trades', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[deal(ticket: 'shared')]);

      await s.service.syncAccount(account(id: 'acc-1'));
      final TradeSyncOutcome other =
          await s.service.syncAccount(account(id: 'acc-2'));

      // Account isolation: the same provider id in a different account is NOT a duplicate.
      expect(other.imported, 1);
      expect(s.trades.records.length, 2);
    });
group('malformed provider records', () {
    test('a record with no id is skipped, the rest import', () async {
      final s = build();
      final Map<String, dynamic> noId = deal(ticket: 'ok')..remove('ticket');
      s.source.replaceAll(<Map<String, dynamic>>[noId, deal(ticket: 'good')]);
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);

      expect(outcome.imported, 1);
      expect(s.trades.records.single.externalId, 'good');
      expect(
        outcome.issues.map((ImportIssue i) => i.code),
        contains(ImportIssueCode.missingRequiredField),
      );
    });

    test('a record with no symbol is skipped', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[deal()..remove('symbol')]);
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);
      expect(outcome.imported, 0);
      expect(outcome.isPartial, isTrue);
    });

    test('an impossible volume is skipped', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[
        deal(ticket: 'zero', volume: 0),
        deal(ticket: 'neg', volume: -1),
        deal(ticket: 'ok'),
      ]);
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);

      expect(outcome.imported, 1);
      expect(
        outcome.issues.map((ImportIssue i) => i.code),
        contains(ImportIssueCode.invalidVolume),
      );
    });

    test('an unreadable direction is skipped', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[
        deal(ticket: 'weird', type: 'sideways'),
        deal(ticket: 'ok'),
      ]);
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);

      expect(outcome.imported, 1);
      expect(
        outcome.issues.map((ImportIssue i) => i.code),
        contains(ImportIssueCode.unsupportedDirection),
      );
    });

    test('a bad optional price degrades to null rather than dropping', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[deal()..['sl'] = 'oops']);
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);

      expect(outcome.imported, 1);
      expect(s.trades.records.single.stopLoss, isNull);
    });

    test('an unreadable pnl never becomes NaN', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[deal(profit: 'oops')]);
      await s.service.syncAccount(acc);
      expect(s.trades.records.single.netPnl.isFinite, isTrue);
    });
  });
  });
group('provider failures', () {
    test('an expired credential is reported as trader-safe copy', () async {
      final s = build();
      s.source.failure = TradeSyncFailure.authFailed;
      await expectLater(
        s.service.syncAccount(acc),
        throwsA(
          isA<TradeSyncException>()
              .having((TradeSyncException e) => e.failure, 'failure',
                  TradeSyncFailure.authFailed,)
              .having((TradeSyncException e) => e.message, 'message',
                  contains('Reconnect'),),
        ),
      );
      expect(s.trades.records, isEmpty);
    });

    test('a rate-limited provider surfaces the retry hint', () async {
      final s = build();
      s.source
        ..failure = TradeSyncFailure.rateLimited
        ..retryAfter = const Duration(seconds: 42);
      try {
        await s.service.syncAccount(acc);
        fail('expected a TradeSyncException');
      } on TradeSyncException catch (e) {
        expect(e.failure, TradeSyncFailure.rateLimited);
        expect(e.retryAfter, const Duration(seconds: 42));
        expect(e.isRetryable, isTrue);
      }
    });

    test('a network failure never leaks the raw error', () async {
      final s = build();
      s.source.failure = TradeSyncFailure.network;
      try {
        await s.service.syncAccount(acc);
        fail('expected a TradeSyncException');
      } on TradeSyncException catch (e) {
        expect(e.failure, TradeSyncFailure.network);
        expect(e.message, isNot(contains('SocketException')));
        // The technical detail is kept for diagnostics only.
        expect(e.detail, contains('SocketException'));
      }
    });

    test('a malformed provider response is reported safely', () async {
      final s = build();
      s.source.failure = TradeSyncFailure.malformedResponse;
      try {
        await s.service.syncAccount(acc);
        fail('expected a TradeSyncException');
      } on TradeSyncException catch (e) {
        expect(e.failure, TradeSyncFailure.malformedResponse);
        expect(e.message, isNot(contains('<html>')));
      }
    });

    test('an unconfigured account is refused before any provider call',
        () async {
      final s = build();
      await expectLater(
        s.service.syncAccount(account(providerId: null)),
        throwsA(
          isA<TradeSyncException>().having((TradeSyncException e) => e.failure,
              'failure', TradeSyncFailure.notConfigured,),
        ),
      );
      expect(s.source.calls, isEmpty);
    });

    test('a failure does not advance the watermark', () async {
      final s = build();
      s.source.failure = TradeSyncFailure.network;
      await expectLater(
        s.service.syncAccount(acc),
        throwsA(isA<TradeSyncException>()),
      );
      final TradeSyncCursor cursor = (await s.cursors.read('acc-1'))!;
      // Crucial: the next run must re-read this window, not skip past it.
      expect(cursor.lastSyncedAt, isNull);
      expect(cursor.isFirstRun, isTrue);
      expect(cursor.consecutiveFailures, 1);
    });

    test('a retry after a failure re-reads the same window', () async {
      final s = build();
      s.source.failure = TradeSyncFailure.network;
      await expectLater(
        s.service.syncAccount(acc),
        throwsA(isA<TradeSyncException>()),
      );
      // Rewind past the backoff window to model "the scheduler runs again later".
      await s.cursors.write(
        TradeSyncCursor(
          accountId: 'acc-1',
          lastRunAt: now.subtract(const Duration(hours: 2)),
          consecutiveFailures: 1,
        ),
      );
      final TradeSyncOutcome recovered = await s.service.syncAccount(acc);
      expect(recovered.imported, 3);
      expect((await s.cursors.read('acc-1'))!.consecutiveFailures, 0);
    });
test('backoff stops a failing account being retried immediately', () async {
      final s = build(
        seedCursors: <TradeSyncCursor>[
          TradeSyncCursor(
            accountId: 'acc-1',
            lastRunAt: now.subtract(const Duration(seconds: 10)),
            consecutiveFailures: 3,
          ),
        ],
      );
      await expectLater(
        s.service.syncAccount(acc),
        throwsA(
          isA<TradeSyncException>().having((TradeSyncException e) => e.failure,
              'failure', TradeSyncFailure.rateLimited,),
        ),
      );
      // No provider call was spent during the backoff window.
      expect(s.source.calls, isEmpty);
    });

    test('a partial provider page still writes the good records', () async {
      final s = build();
      s.source.replaceAll(<Map<String, dynamic>>[
        deal(ticket: 'good'),
        deal()..remove('ticket'),
        deal(ticket: 'badvol', volume: 0),
        deal(ticket: 'good3'),
      ]);
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);

      expect(outcome.fetched, 4);
      expect(outcome.imported, 2);
      expect(outcome.issues.length, 2);
      expect(outcome.isPartial, isTrue);
      expect(s.trades.records.length, 2);
    });

    test('a repository failure surfaces safe copy and holds the cursor',
        () async {
      final InMemoryTradeSyncCursorRepository cursors =
          InMemoryTradeSyncCursorRepository();
      final TradeSyncService service = TradeSyncService(
        source: MockTradeSyncSource(),
        trades: _ExplodingRepository(),
        cursors: cursors,
        clock: () => now,
      );
      await expectLater(
        service.syncAccount(acc),
        throwsA(
          isA<TradeSyncException>()
              .having((TradeSyncException e) => e.failure, 'failure',
                  TradeSyncFailure.persistenceFailed,)
              .having((TradeSyncException e) => e.message, 'message',
                  isNot(contains('SQLSTATE')),)
              .having((TradeSyncException e) => e.message, 'message',
                  isNot(contains('pgx')),),
        ),
      );
      // The watermark must not move, or those trades would be lost for good.
      expect((await cursors.read('acc-1'))!.lastSyncedAt, isNull);
    });
  });
group('account isolation', () {
    test('each account gets its own cursor', () async {
      final s = build();
      await s.service.syncAccount(account(id: 'acc-1'));
      await s.service.syncAccount(account(id: 'acc-2'));

      expect((await s.cursors.read('acc-1'))!.lastSyncedAt, now);
      expect((await s.cursors.read('acc-2'))!.lastSyncedAt, now);
    });

    test('a disabled account is skipped by a batch run', () async {
      final s = build();
      final List<TradeSyncOutcome> outcomes = await s.service.syncAccounts(
        <SyncableAccount>[
          account(id: 'acc-1'),
          account(id: 'acc-2', enabled: false),
        ],
      );
      expect(outcomes.length, 1);
      expect(outcomes.single.accountId, 'acc-1');
      expect(await s.cursors.read('acc-2'), isNull);
    });

    test('one failing account does not stop the others', () async {
      final InMemoryTradeImportRepository trades = InMemoryTradeImportRepository();
      final TradeSyncService service = TradeSyncService(
        source: MockTradeSyncSource(),
        trades: trades,
        cursors: InMemoryTradeSyncCursorRepository(),
        clock: () => now,
      );

      // The first account is not configured, so it throws; the second must still sync.
      final List<TradeSyncOutcome> outcomes = await service.syncAccounts(
        <SyncableAccount>[
          account(id: 'acc-broken', providerId: null),
          account(id: 'acc-2'),
        ],
      );
      expect(outcomes.length, 1);
      expect(outcomes.single.accountId, 'acc-2');
    });

    test('the cursor repository can scope to one owner', () async {
      final InMemoryTradeSyncCursorRepository cursors =
          InMemoryTradeSyncCursorRepository();
      await cursors.write(const TradeSyncCursor(accountId: 'acc-1'));
      cursors.owners['acc-1'] = 'user-1';

      expect((await cursors.listEligible(userId: 'user-1')).length, 1);
      expect((await cursors.listEligible(userId: 'user-2')).length, 0);
    });
  });

  group('no secret leakage', () {
    test('no provider credential appears in the outcome or the cursor',
        () async {
      final s = build();
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);
      final TradeSyncCursor cursor = (await s.cursors.read('acc-1'))!;

      for (final Object? value in <Object?>[
        outcome.toSummary(),
        outcome.toString(),
        cursor.toString(),
      ]) {
        expect('$value', isNot(contains('Bearer')));
        expect('$value', isNot(contains('password')));
      }
    });

    test('the outcome carries only counts', () async {
      final s = build();
      final TradeSyncOutcome outcome = await s.service.syncAccount(acc);
      expect(
        outcome.toSummary().keys,
        <String>{
          'account_id',
          'fetched',
          'imported',
          'updated',
          'skipped',
          'pages',
        },
      );
    });
  });
}

/// Fails like a backend would, to prove provider errors never reach the UI verbatim.
class _ExplodingRepository implements TradeImportRepository {
  @override
  Future<Set<String>> existingExternalIds(String accountId) async => <String>{};

  @override
  Future<int> saveTrades(
    String accountId,
    List<TradeRecord> records, {
    DuplicateStrategy strategy = DuplicateStrategy.skipExisting,
  }) async {
    throw StateError(
      'pgx: duplicate key value violates unique constraint '
      '"trades_user_id_external_id_key" (SQLSTATE 23505)',
    );
  }
}
