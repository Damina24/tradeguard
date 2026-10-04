import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/trade.dart';
import 'package:tradeguard/features/import/data/csv_trade_parser.dart';
import 'package:tradeguard/features/import/data/trade_file_parser.dart';
import 'package:tradeguard/features/import/domain/import_issue.dart';
import 'package:tradeguard/features/import/domain/trade_record.dart';

/// A realistic broker statement header, with broker-flavoured column names.
///
/// Order matters: the fixture rows below line up with these columns exactly, so a test cannot
/// pass for the wrong reason.
const String _csvHeader =
    'Ticket,Time,Type,Volume,Symbol,Open,Close,S/L,T/P,S/L/TP,Commission,Swap,'
    'Profit,Currency';

/// 1001 / long 0.50 XAUUSD / +312.00 gross / -3.50 commission / -0.70 swap.
const String _goldBuy = '1001,2026-04-15 08:30:00,buy,0.50,XAUUSD,2345.10,'
    '2351.40,2340.00,2351.40,2351.40,-3.50,-0.70,312.00,USD';

const String _eurSell = '1002,2026-04-16 09:00:00,sell,1.00,EURUSD,1.0850,'
    '1.0810,1.0870,1.0800,1.0810,-2.40,-1.20,-40.00,USD';

ParseOutcome parseCsv(String body) => const CsvTradeParser().parse(
      ImportSource(content: body, fileName: 'history.csv'),
    );

/// Asserts the parse fails, and returns the exception so its per-row issues can be checked.
TradeImportException _expectFailure(String csv) {
  try {
    parseCsv(csv);
    fail('expected a TradeImportException');
  } on TradeImportException catch (e) {
    return e;
  }
}

void main() {
group('valid CSV', () {
    test('reads one trade with every optional field', () {
      final ParseOutcome out = parseCsv('$_csvHeader\n$_goldBuy');
      expect(out.records.length, 1);
      expect(out.issues, isEmpty);

      final TradeRecord t = out.records.single;
      expect(t.externalId, '1001');
      expect(t.symbol, 'XAUUSD');
      expect(t.direction, TradeDirection.long);
      expect(t.volumeLots, 0.5);
      expect(t.entryPrice, 2345.10);
      expect(t.exitPrice, 2351.40);
      expect(t.stopLoss, 2340.00);
      expect(t.takeProfit, 2351.40);
      expect(t.profit, 312.00);
      expect(t.commission, -3.50);
      expect(t.swap, -0.70);
      expect(t.currency, 'USD');
      expect(t.openTime, DateTime.utc(2026, 4, 15, 8, 30));
    });

    test('netPnl folds in commission and swap', () {
      final TradeRecord t = parseCsv('$_csvHeader\n$_goldBuy').records.single;
      // 312.00 - 3.50 - 0.70
      expect(t.netPnl, closeTo(307.80, 0.0001));
    });

    test('reads multiple trades', () {
      final ParseOutcome out = parseCsv('$_csvHeader\n$_goldBuy\n$_eurSell');
      expect(out.records.length, 2);
      expect(
        out.records.map((TradeRecord r) => r.externalId),
        <String>['1001', '1002'],
      );
    });

    test('handles multiple symbols', () {
      final ParseOutcome out = parseCsv(
        '$_csvHeader\n$_goldBuy\n'
        '1002,2026-04-16 09:00:00,buy,0.10,GBPJPY,199.40,200.00,199.00,200.00,'
        '0,0.00,0.00,10.00,USD\n'
        '1003,2026-04-17 09:00:00,buy,0.20,US30,40000,40100,39900,40100,'
        '0,-20.00,0.00,200.00,USD',
      );
      expect(
        out.records.map((TradeRecord r) => r.symbol).toSet(),
        <String>{'XAUUSD', 'GBPJPY', 'US30'},
      );
    });

    test('handles buy and sell in one file', () {
      final ParseOutcome out = parseCsv('$_csvHeader\n$_goldBuy\n$_eurSell');
      expect(out.records.first.direction, TradeDirection.long);
      expect(out.records.last.direction, TradeDirection.short);
    });

    test('imports when every optional column is absent', () {
      final ParseOutcome out = parseCsv(
        'Ticket,Type,Volume,Symbol\n2001,buy,0.30,EURUSD\n',
      );
      expect(out.records.length, 1);
      final TradeRecord t = out.records.single;
      expect(t.entryPrice, isNull);
      expect(t.exitPrice, isNull);
      expect(t.stopLoss, isNull);
      expect(t.takeProfit, isNull);
      expect(t.profit, 0);
      expect(t.commission, 0);
      expect(t.swap, 0);
      expect(t.openTime, isNull);
      expect(t.closeTime, isNull);
      expect(t.currency, isNull);
      expect(t.broker, isNull);
    });

    test('normalizes a broker symbol suffix', () {
      final ParseOutcome out = parseCsv(
        '$_csvHeader\n'
        '1001,2026-04-15 08:30:00,buy,0.50,XAUUSD.m,2345.10,2351.40,2340.00,'
        '2351.40,2351.40,-3.50,-0.70,312.00,USD',
      );
      expect(out.records.single.symbol, 'XAUUSD');
    });

    test('skips a title row above the header', () {
      final ParseOutcome out =
          parseCsv('Account statement\n$_csvHeader\n$_goldBuy');
      expect(out.records.length, 1);
    });

    test('handles a quoted value containing a comma', () {
      final ParseOutcome out = parseCsv(
        'Ticket,Type,Volume,Symbol,Comment\n'
        '3001,buy,0.50,EURUSD,"London, breakout"\n',
      );
      expect(out.records.length, 1);
      expect(out.records.single.symbol, 'EURUSD');
    });
  });

  group('CSV whole-file failures', () {
    test('empty file is refused', () {
      expect(
        () => parseCsv('   '),
        throwsA(
          isA<TradeImportException>().having(
            (TradeImportException e) => e.code,
            'code',
            ImportIssueCode.emptyFile,
          ),
        ),
      );
    });

    test('header with no data rows is refused', () {
      expect(
        () => parseCsv('$_csvHeader\n'),
        throwsA(
          isA<TradeImportException>().having(
            (TradeImportException e) => e.code,
            'code',
            ImportIssueCode.emptyFile,
          ),
        ),
      );
    });

    test('missing required columns are named in trader-safe copy', () {
      expect(
        () => parseCsv('Foo,Bar\n1,2\n'),
        throwsA(
          isA<TradeImportException>()
              .having((TradeImportException e) => e.code, 'code',
                  ImportIssueCode.missingRequiredColumns,)
              .having(
                (TradeImportException e) => e.message,
                'message',
                allOf(contains('trade ID'), contains('symbol')),
              ),
        ),
      );
    });

    test('a header missing only direction says so', () {
      expect(
        () => parseCsv('Ticket,Volume,Symbol\n1,0.5,EURUSD\n'),
        throwsA(
          isA<TradeImportException>().having(
            (TradeImportException e) => e.message,
            'message',
            contains('direction'),
          ),
        ),
      );
    });

    test('malformed CSV maps to malformedFile', () {
      expect(
        () => parseCsv('$_csvHeader\n"unclosed,1001,buy,0.5'),
        throwsA(
          isA<TradeImportException>().having((TradeImportException e) => e.code,
              'code', ImportIssueCode.malformedFile,),
        ),
      );
    });

    test('the raw parser message never reaches the trader', () {
      final TradeImportException e =
          _expectFailure('$_csvHeader\n"unclosed,1001,buy,0.5');
      expect(e.message, isNot(contains('CsvParser')));
      expect(e.message, isNot(contains('InvalidCsv')));
      expect(e.message, isNot(contains('textEndDelimiter')));
      // ...but the technical detail is retained for diagnostics.
      expect(e.detail, isNotNull);
    });
  });
group('CSV row validation', () {
    test('a bad row is skipped while the good rows survive', () {
      final ParseOutcome out = parseCsv(
        '$_csvHeader\n$_goldBuy\n'
        '1003,2026-04-17 09:00:00,sell,1.00,EURUSD,1.0850,1.0810,1.0870,1.0800,'
        '1.0810,abc,-1.20,-40.00,USD',
      );
      expect(out.records.length, 1);
      expect(out.records.single.externalId, '1001');
      expect(
        out.issues.map((ImportIssue i) => i.code),
        contains(ImportIssueCode.invalidNumber),
      );
    });

    test('invalid date drops the row and is reported', () {
      final TradeImportException e = _expectFailure(
        '$_csvHeader\n'
        '1001,31/02/2026 08:30:00,buy,0.50,XAUUSD,2345.10,2351.40,2340.00,'
        '2351.40,2351.40,-3.50,-0.70,312.00,USD',
      );
      expect(
        e.issues.map((ImportIssue i) => i.code),
        contains(ImportIssueCode.invalidDate),
      );
    });

    test('unsupported direction drops the row', () {
      final TradeImportException e = _expectFailure(
        '$_csvHeader\n'
        '1001,2026-04-15 08:30:00,sideways,0.50,XAUUSD,2345.10,2351.40,'
        '2340.00,2351.40,2351.40,-3.50,-0.70,312.00,USD',
      );
      expect(
        e.issues.map((ImportIssue i) => i.code),
        contains(ImportIssueCode.unsupportedDirection),
      );
    });

    test('zero volume drops the row', () {
      final TradeImportException e = _expectFailure(
        '$_csvHeader\n'
        '1001,2026-04-15 08:30:00,buy,0,XAUUSD,2345.10,2351.40,2340.00,'
        '2351.40,2351.40,-3.50,-0.70,312.00,USD',
      );
      expect(
        e.issues.map((ImportIssue i) => i.code),
        contains(ImportIssueCode.invalidVolume),
      );
    });

    test('negative volume drops the row', () {
      final TradeImportException e = _expectFailure(
        '$_csvHeader\n'
        '1001,2026-04-15 08:30:00,buy,-1,XAUUSD,2345.10,2351.40,2340.00,'
        '2351.40,2351.40,-3.50,-0.70,312.00,USD',
      );
      expect(
        e.issues.map((ImportIssue i) => i.code),
        contains(ImportIssueCode.invalidVolume),
      );
    });

    test('blank required value drops the row', () {
      final TradeImportException e = _expectFailure(
        '$_csvHeader\n'
        ',2026-04-15 08:30:00,buy,0.50,XAUUSD,2345.10,2351.40,2340.00,'
        '2351.40,2351.40,-3.50,-0.70,312.00,USD',
      );
      expect(
        e.issues.map((ImportIssue i) => i.code),
        contains(ImportIssueCode.missingRequiredField),
      );
    });

    test('a short row is malformed rather than shifted', () {
      final TradeImportException e =
          _expectFailure('$_csvHeader\n1001,2026-04-15 08:30:00,buy\n');
      expect(
        e.issues.map((ImportIssue i) => i.code),
        contains(ImportIssueCode.malformedRow),
      );
    });

    test('issue copy never leaks a broker column name', () {
      final TradeImportException e = _expectFailure(
        '$_csvHeader\n'
        '1002,2026-04-16 09:00:00,sideways,1.00,EURUSD,1.0850,1.0810,1.0870,'
        '1.0800,1.0810,abc,-1.20,-40.00,USD',
      );
      expect(e.issues, isNotEmpty);
      for (final ImportIssue i in e.issues) {
        expect(i.message, isNot(contains('Ticket')));
        expect(i.message, isNot(contains('S/L/TP')));
      }
    });
  });
}