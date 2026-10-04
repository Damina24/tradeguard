import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/trade.dart';
import 'package:tradeguard/features/import/data/csv_trade_parser.dart';
import 'package:tradeguard/features/import/data/html_trade_parser.dart';
import 'package:tradeguard/features/import/data/trade_file_parser.dart';
import 'package:tradeguard/features/import/data/trade_parser_registry.dart';
import 'package:tradeguard/features/import/domain/import_issue.dart';
import 'package:tradeguard/features/import/domain/trade_record.dart';

/// A broker "Save as HTML" statement: a title, a nav table that is not trades, then the real
/// trade table.
String html(String body) => '''
<html>
<head><title>Trade History</title></head>
<body>
<h1>Trade History</h1>
<table><tr><th>Account</th><th>Balance</th></tr>
<tr><td>12345</td><td>10000</td></tr></table>
<table>
<tr><th>Deal</th><th>Time</th><th>Type</th><th>Volume</th><th>Symbol</th>
    <th>Open</th><th>Close</th><th>S/L</th><th>T/P</th>
    <th>Commission</th><th>Swap</th><th>Profit</th></tr>
$body
</table>
</body>
</html>
''';

ParseOutcome parseHtml(String body) => const HtmlTradeParser().parse(
      ImportSource(content: html(body), fileName: 'history.html'),
    );

const String _goldRow =
    '<tr><td>1001</td><td>2026-04-15 08:30:00</td><td>buy</td><td>0.50</td>'
    '<td>XAUUSD</td><td>2345.10</td><td>2351.40</td><td>2340.00</td>'
    '<td>2351.40</td><td>-3.50</td><td>-0.70</td><td>312.00</td></tr>';

void main() {
  group('valid HTML', () {
    test('reads one trade from the trade table', () {
      final ParseOutcome out = parseHtml(_goldRow);
      expect(out.records.length, 1);

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
      expect(t.openTime, DateTime.utc(2026, 4, 15, 8, 30));
    });

    test('ignores a non-trade table above the real one', () {
      // The Account/Balance table is in every fixture and must not be read as trades.
      expect(parseHtml(_goldRow).records.length, 1);
    });

    test('reads multiple trades and directions', () {
      final ParseOutcome out = parseHtml(
        '$_goldRow'
        '<tr><td>1002</td><td>2026-04-16 09:00:00</td><td>sell</td>'
        '<td>1.00</td><td>EURUSD</td><td>1.0850</td><td>1.0810</td>'
        '<td>1.0870</td><td>1.0800</td><td>-2.40</td><td>-1.20</td>'
        '<td>-40.00</td></tr>',
      );
      expect(out.records.length, 2);
      expect(
        out.records.map((TradeRecord r) => r.direction),
        <TradeDirection>[TradeDirection.long, TradeDirection.short],
      );
      expect(
        out.records.map((TradeRecord r) => r.symbol).toSet(),
        <String>{'XAUUSD', 'EURUSD'},
      );
    });

    test('decodes entities and collapses whitespace in cells', () {
      final ParseOutcome out = parseHtml(
        '<tr><td>1001</td><td>2026-04-15 08:30:00</td><td>buy</td>'
        '<td>0.50</td><td>XAUUSD &amp; more</td><td>2345.10</td>'
        '<td>2351.40</td><td>2340.00</td><td>2351.40</td><td>-3.50</td>'
        '<td>-0.70</td><td>312.00</td></tr>',
      );
      expect(out.records.single.symbol, 'XAUUSD&MORE');
    });

    test('reads a non-breaking-space-padded cell', () {
      final ParseOutcome out = parseHtml(
        '<tr><td>1001</td><td>2026-04-15 08:30:00</td><td>buy</td>'
        '<td>&nbsp;0.50&nbsp;</td><td>XAUUSD</td><td>2345.10</td>'
        '<td>2351.40</td><td>2340.00</td><td>2351.40</td><td>-3.50</td>'
        '<td>-0.70</td><td>312.00</td></tr>',
      );
      expect(out.records.single.volumeLots, 0.5);
    });

    test('imports when optional columns are absent', () {
      final ParseOutcome out = const HtmlTradeParser().parse(
        const ImportSource(
          fileName: 'minimal.html',
          content: '<html><body><table>'
              '<tr><th>Deal</th><th>Type</th><th>Volume</th><th>Symbol</th></tr>'
              '<tr><td>1001</td><td>buy</td><td>0.30</td><td>EURUSD</td></tr>'
              '</table></body></html>',
        ),
      );
      expect(out.records.length, 1);
      expect(out.records.single.entryPrice, isNull);
      expect(out.records.single.profit, 0);
    });
  });
group('HTML failures', () {
    test('empty file is refused', () {
      expect(
        () => const HtmlTradeParser().parse(
          const ImportSource(content: '   ', fileName: 'x.html'),
        ),
        throwsA(
          isA<TradeImportException>().having(
            (TradeImportException e) => e.code,
            'code',
            ImportIssueCode.emptyFile,
          ),
        ),
      );
    });

    test('a document with no table is refused', () {
      expect(
        () => const HtmlTradeParser().parse(
          const ImportSource(
            content: '<html><body><p>Nothing here</p></body></html>',
            fileName: 'x.html',
          ),
        ),
        throwsA(
          isA<TradeImportException>().having(
            (TradeImportException e) => e.code,
            'code',
            ImportIssueCode.unsupportedFileStructure,
          ),
        ),
      );
    });

    test('malformed HTML with no trade columns is refused', () {
      expect(
        () => const HtmlTradeParser().parse(
          const ImportSource(
            content: '<html><body><table><tr><th>Foo</th><th>Bar</th></tr>'
                '<tr><td>1</td><td>2</td></tr></table></body>',
            fileName: 'x.html',
          ),
        ),
        throwsA(
          isA<TradeImportException>().having(
            (TradeImportException e) => e.code,
            'code',
            ImportIssueCode.missingRequiredColumns,
          ),
        ),
      );
    });

    test('unclosed tags are tolerated, not rejected', () {
      // Real statements are full of unclosed <td>/<tr>; that must not lose the trades.
      final ParseOutcome out = const HtmlTradeParser().parse(
        const ImportSource(
          fileName: 'x.html',
          content: '<html><body><table>'
              '<tr><th>Deal<th>Type<th>Volume<th>Symbol'
              '<tr><td>1001<td>buy<td>0.50<td>XAUUSD'
              '</table>',
        ),
      );
      expect(out.records.length, 1);
      expect(out.records.single.symbol, 'XAUUSD');
    });

    test('a row with an unreadable direction is reported', () {
      final ParseOutcome out = parseHtml(
        '$_goldRow'
        '<tr><td>1003</td><td>2026-04-17 09:00:00</td><td>sideways</td>'
        '<td>1.00</td><td>EURUSD</td><td>1.0850</td><td>1.0810</td>'
        '<td>1.0870</td><td>1.0800</td><td>-2.40</td><td>-1.20</td>'
        '<td>-40.00</td></tr>',
      );
      expect(out.records.length, 1);
      expect(
        out.issues.map((ImportIssue i) => i.code),
        contains(ImportIssueCode.unsupportedDirection),
      );
    });

    test('a short row is malformed rather than shifted', () {
      final ParseOutcome out = parseHtml(
        '$_goldRow'
        '<tr><td>1003</td><td>2026-04-17</td></tr>',
      );
      expect(out.records.length, 1);
      expect(
        out.issues.map((ImportIssue i) => i.code),
        contains(ImportIssueCode.malformedRow),
      );
    });

    test('no parser detail leaks into the user-facing message', () {
      try {
        const HtmlTradeParser().parse(
          const ImportSource(content: '<html><p>no tables</p></html>',
              fileName: 'x.html',),
        );
        fail('expected a TradeImportException');
      } on TradeImportException catch (e) {
        expect(e.message, isNot(contains('RegExp')));
        expect(e.message, isNot(contains('Exception')));
        expect(e.message, isNot(contains('null')));
      }
    });
  });

  group('format detection', () {
    test('the registry routes CSV and HTML by extension', () {
      final TradeParserRegistry registry = TradeParserRegistry();
      expect(
        registry
            .select(const ImportSource(content: 'a,b\n1,2', fileName: 'x.csv'))
            .formatName,
        'CSV',
      );
      expect(
        registry
            .select(const ImportSource(content: '<html></html>', fileName: 'x.html'))
            .formatName,
        'HTML',
      );
    });

    test('the registry sniffs content when the name is unhelpful', () {
      final TradeParserRegistry registry = TradeParserRegistry();
      expect(
        registry
            .select(const ImportSource(content: '<html><table></table></html>'))
            .formatName,
        'HTML',
      );
    });

    test('an unsupported file type is refused in trader-safe copy', () {
      final TradeParserRegistry registry = TradeParserRegistry();
      expect(
        () => registry.select(
          const ImportSource(content: 'binary', fileName: 'statement.pdf'),
        ),
        throwsA(
          isA<TradeImportException>()
              .having((TradeImportException e) => e.code, 'code',
                  ImportIssueCode.unsupportedFileStructure,)
              .having((TradeImportException e) => e.message, 'message',
                  contains('CSV'),),
        ),
      );
    });

    test('an HTML document is never handed to the CSV parser', () {
      const CsvTradeParser csv = CsvTradeParser();
      expect(
        csv.canParse(
          const ImportSource(content: '<html><table></table></html>',
              fileName: 'statement.txt',),
        ),
        isFalse,
      );
    });
  });
}