import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/trade.dart';
import 'package:tradeguard/features/import/data/trade_file_parser.dart';
import 'package:tradeguard/features/import/data/trade_import_repository.dart';
import 'package:tradeguard/features/import/data/trade_parser_registry.dart';
import 'package:tradeguard/features/import/domain/import_issue.dart';
import 'package:tradeguard/features/import/domain/trade_record.dart';
import 'package:tradeguard/features/import/trade_import_service.dart';

const String _header =
    'Ticket,Time,Type,Volume,Symbol,Open,Close,S/L,T/P,Commission,Swap,Profit';

const String _row1 = '1001,2026-04-15 08:30:00,buy,0.50,XAUUSD,2345.10,'
    '2351.40,2340.00,2351.40,-3.50,-0.70,312.00';

const String _row2 = '1002,2026-04-16 09:00:00,sell,1.00,EURUSD,1.0850,'
    '1.0810,1.0870,1.0800,-2.40,-1.20,-40.00';

ImportSource csv(String body) =>
    ImportSource(content: '$_header\n$body', fileName: 'history.csv');

/// A service wired to a fresh in-memory repository, so no test sees another's writes.
({TradeImportService service, InMemoryTradeImportRepository repo}) build() {
  final InMemoryTradeImportRepository repo = InMemoryTradeImportRepository();
  return (
    service: TradeImportService(
      registry: TradeParserRegistry(),
      repository: repo,
    ),
    repo: repo,
  );
}

TradeRecord record(String id, {double profit = 100}) => TradeRecord(
      externalId: id,
      symbol: 'XAUUSD',
      direction: TradeDirection.long,
      volumeLots: 0.5,
      profit: profit,
    );

void main() {
  group('happy path', () {
    test('persists normalized TradeRecords', () async {
      final ({TradeImportService service, InMemoryTradeImportRepository repo}) s =
          build();
      final TradeImportResult result = await s.service.importFile(
        csv(_row1),
        accountId: 'acc_eval_100k',
      );
      expect(result.imported.length, 1);
      expect(result.issues, isEmpty);
      expect(result.duplicateCount, 0);
      expect(s.repo.records.length, 1);

      final TradeRecord saved = s.repo.records.single;
      expect(saved.externalId, '1001');
      expect(saved.symbol, 'XAUUSD');
      expect(saved.direction, TradeDirection.long);
      expect(saved.netPnl, closeTo(307.80, 0.0001));
    });

    test('imports multiple trades into the chosen account', () async {
      final ({TradeImportService service, InMemoryTradeImportRepository repo}) s =
          build();
      final TradeImportResult result = await s.service.importFile(
        csv('$_row1\n$_row2'),
        accountId: 'acc_funded_50k',
      );
      expect(result.imported.length, 2);
      expect(result.accountId, 'acc_funded_50k');
      expect(s.repo.records.length, 2);
      expect(
        s.repo.records.map((TradeRecord r) => r.symbol).toSet(),
        <String>{'XAUUSD', 'EURUSD'},
      );
    });

    test('the repository never receives a raw CSV row', () async {
      final ({TradeImportService service, InMemoryTradeImportRepository repo}) s =
          build();
      await s.service.importFile(csv(_row1), accountId: 'acc');
      final TradeRecord saved = s.repo.records.single;
      // Everything the repository holds is a typed domain object.
      expect(saved.volumeLots, isA<double>());
      expect(saved.direction, isA<TradeDirection>());
      expect(saved.openTime, isA<DateTime>());
      expect(saved.currency, isNull);
    });

    test('summary copy counts what happened', () async {
      final ({TradeImportService service, InMemoryTradeImportRepository repo}) s =
          build();
      final TradeImportResult result = await s.service.importFile(
        csv(_row1),
        accountId: 'acc',
      );
      expect(result.summary, 'Imported 1 trade');
    });

    test('a partial import still writes the good rows', () async {
      final ({TradeImportService service, InMemoryTradeImportRepository repo}) s =
          build();
      final TradeImportResult result = await s.service.importFile(
        csv('$_row1\n'
            '1003,2026-04-17 09:00:00,sideways,1.00,GBPUSD,1.2,1.1,1.3,1.1,'
            '-1.00,0.00,10.00'),
        accountId: 'acc',
      );
      expect(result.imported.length, 1);
      expect(result.issues.length, 1);
      expect(result.isPartial, isTrue);
      expect(result.skipped, 1);
      expect(s.repo.records.length, 1);
      expect(result.summary, contains('1 row skipped'));
    });
  });
group('duplicates', () {
    test('the same identifier twice in one file keeps the first', () async {
      final ({TradeImportService service, InMemoryTradeImportRepository repo}) s =
          build();
      final TradeImportResult result = await s.service.importFile(
        csv('$_row1\n$_row1'),
        accountId: 'acc',
      );
      expect(result.imported.length, 1);
      expect(
        result.issues.map((ImportIssue i) => i.code),
        contains(ImportIssueCode.duplicateTradeId),
      );
      expect(s.repo.records.length, 1);
    });

    test('re-importing the same file creates no duplicates', () async {
      final ({TradeImportService service, InMemoryTradeImportRepository repo}) s =
          build();
      await s.service.importFile(csv('$_row1\n$_row2'), accountId: 'acc');
      expect(s.repo.records.length, 2);

      final TradeImportResult again = await s.service.importFile(
        csv('$_row1\n$_row2'),
        accountId: 'acc',
      );
      expect(again.imported, isEmpty);
      expect(again.duplicateCount, 2);
      // The decisive assertion: P&L is not doubled.
      expect(s.repo.records.length, 2);
      expect(again.summary, contains('2 already in this account'));
    });

    test('skipExisting is the default', () async {
      final ({TradeImportService service, InMemoryTradeImportRepository repo}) s =
          build();
      await s.service.importFile(csv(_row1), accountId: 'acc');
      final TradeImportResult again =
          await s.service.importFile(csv(_row1), accountId: 'acc');
      expect(again.strategy, DuplicateStrategy.skipExisting);
      expect(again.imported, isEmpty);
    });

    test('replaceExisting overwrites the stored trade', () async {
      final ({TradeImportService service, InMemoryTradeImportRepository repo}) s =
          build();
      await s.service.importFile(csv(_row1), accountId: 'acc');

      // The broker restates the profit on the same ticket.
      final TradeImportResult result = await s.service.importFile(
        csv('1001,2026-04-15 08:30:00,buy,0.50,XAUUSD,2345.10,2351.40,2340.00,'
            '2351.40,-3.50,-0.70,999.00'),
        accountId: 'acc',
        strategy: DuplicateStrategy.replaceExisting,
      );
      expect(result.imported.length, 1);
      expect(s.repo.records.length, 1);
      expect(s.repo.records.single.profit, 999.00);
    });

    test('fail refuses the whole import when anything clashes', () async {
      final ({TradeImportService service, InMemoryTradeImportRepository repo}) s =
          build();
      await s.service.importFile(csv(_row1), accountId: 'acc');

      await expectLater(
        s.service.importFile(
          csv('$_row1\n$_row2'),
          accountId: 'acc',
          strategy: DuplicateStrategy.fail,
        ),
        throwsA(
          isA<TradeImportException>().having(
            (TradeImportException e) => e.code,
            'code',
            ImportIssueCode.duplicateTradeIdInAccount,
          ),
        ),
      );
      // Nothing partial: _row2 must NOT have been written.
      expect(s.repo.records.length, 1);
      expect(
        s.repo.records.map((TradeRecord r) => r.externalId),
        <String>['1001'],
      );
    });

    test('duplicates are scoped to the target account', () async {
      final ({TradeImportService service, InMemoryTradeImportRepository repo}) s =
          build();
      await s.service.importFile(csv(_row1), accountId: 'acc_a');
      // A different account must not be blocked by the same ticket id.
      final TradeImportResult result = await s.service.importFile(
        csv(_row1),
        accountId: 'acc_b',
      );
      expect(result.imported.length, 1);
      expect(result.duplicateCount, 0);
    });
  });
group('errors', () {
    test('an empty file is refused', () async {
      final ({TradeImportService service, InMemoryTradeImportRepository repo}) s =
          build();
      await expectLater(
        s.service.importFile(csv(''), accountId: 'acc'),
        throwsA(
          isA<TradeImportException>().having(
            (TradeImportException e) => e.code,
            'code',
            ImportIssueCode.emptyFile,
          ),
        ),
      );
      expect(s.repo.records, isEmpty);
    });

    test('the failure message is trader-safe', () async {
      final ({TradeImportService service, InMemoryTradeImportRepository repo}) s =
          build();
      try {
        await s.service.importFile(
          const ImportSource(
            content: '$_header\n"unclosed,1,buy,0.5',
            fileName: 'bad.csv',
          ),
          accountId: 'acc',
        );
        fail('expected a TradeImportException');
      } on TradeImportException catch (e) {
        expect(e.message, isNot(contains('CsvParser')));
        expect(e.message, isNot(contains('InvalidCsvException')));
        expect(e.message, isNot(contains('FormatException')));
      }
    });

    test('a repository failure is surfaced with safe copy', () async {
      final TradeImportService service = TradeImportService(
        registry: TradeParserRegistry(),
        repository: _ExplodingRepository(),
      );
      await expectLater(
        service.importFile(csv(_row1), accountId: 'acc'),
        throwsA(
          isA<TradeImportException>()
              .having((TradeImportException e) => e.message, 'message',
                  contains('could not be saved'),)
              .having((TradeImportException e) => e.message, 'message',
                  isNot(contains('SQLSTATE')),)
              .having((TradeImportException e) => e.message, 'message',
                  isNot(contains('pgx')),),
        ),
      );
    });
  });

  group('repository', () {
    test('is seeded and reports existing identifiers', () async {
      final InMemoryTradeImportRepository repo = InMemoryTradeImportRepository(
        seed: <TradeRecord>[record('1001')],
        seedAccount: 'acc',
      );
      expect(await repo.existingExternalIds('acc'), <String>{'1001'});
      expect(repo.records.length, 1);
    });

    test('exposes an unmodifiable view', () async {
      final InMemoryTradeImportRepository repo = InMemoryTradeImportRepository(
        seed: <TradeRecord>[record('1001')],
        seedAccount: 'acc',
      );
      expect(() => repo.records.add(record('1002')), throwsUnsupportedError);
    });

    test('skipExisting writes nothing for a known id', () async {
      final InMemoryTradeImportRepository repo = InMemoryTradeImportRepository(
        seed: <TradeRecord>[record('1001')],
        seedAccount: 'acc',
      );
      final int written =
          await repo.saveTrades('acc', <TradeRecord>[record('1001')]);
      expect(written, 0);
      expect(repo.records.length, 1);
    });

    test('the same id in another account is not a duplicate', () async {
      final InMemoryTradeImportRepository repo = InMemoryTradeImportRepository(
        seed: <TradeRecord>[record('1001')],
        seedAccount: 'acc',
      );
      final int written =
          await repo.saveTrades('acc_other', <TradeRecord>[record('1001')]);
      expect(written, 1);
      expect(repo.records.length, 2);
    });

    test('fail aborts without writing', () async {
      final InMemoryTradeImportRepository repo = InMemoryTradeImportRepository(
        seed: <TradeRecord>[record('1001')],
        seedAccount: 'acc',
      );
      await expectLater(
        repo.saveTrades(
          'acc',
          <TradeRecord>[record('1001'), record('1002')],
          strategy: DuplicateStrategy.fail,
        ),
        throwsA(isA<TradeImportException>()),
      );
      expect(repo.records.length, 1);
    });
  });
}

/// Fails like a backend would, to prove provider errors never reach the UI verbatim.
class _ExplodingRepository implements TradeImportRepository {
  @override
  Future<Set<String>> existingExternalIds(String accountId) async =>
      <String>{};

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