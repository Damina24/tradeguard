import '../domain/import_issue.dart';
import '../domain/trade_record.dart';
import 'field_aliases.dart';
import 'trade_file_parser.dart';

/// HTML trade-history parser, for the statement pages brokers publish ("Save as HTML").
///
/// Built on the small tag reader below rather than a full DOM engine, so the feature adds no
/// dependency. That is sufficient for the generated, table-based statement documents this
/// targets; anything needing a real CSS-selector engine should be exported as CSV instead.
///
/// Markup is tolerated to a point: unclosed tags are fine, but a document with no readable
/// table, or a table whose header cannot be identified, is a whole-file failure.
class HtmlTradeParser extends TradeFileParser {
  const HtmlTradeParser({super.aliases});

  @override
  String get formatName => 'HTML';

  @override
  bool canParse(ImportSource source) {
    if (source.extension == 'html' || source.extension == 'htm') return true;
    final String head = source.content.substring(
      0,
      source.content.length < 512 ? source.content.length : 512,
    ).toLowerCase();
    return head.contains('<html') || head.contains('<table');
  }

  @override
  ParseOutcome parse(ImportSource source) {
    if (source.isBlank) {
      throw TradeImportException.of(
        ImportIssueCode.emptyFile,
        'That file is empty. Save your trade history as HTML and try again.',
      );
    }

    final List<List<List<String>>> tables = _tables(source.content);
    if (tables.isEmpty) {
      throw TradeImportException.of(
        ImportIssueCode.unsupportedFileStructure,
        'No trade table was found in that HTML file. Save the trade history '
        'table as CSV instead.',
      );
    }

    final TradeRowMapper mapper = TradeRowMapper(aliases ?? FieldAliasTable());
    final List<ImportIssue> issues = <ImportIssue>[];
    final List<TradeRecord> records = <TradeRecord>[];

    for (final List<List<String>> table in tables) {
      if (table.isEmpty) continue;
      final _Table t = _splitHeader(table);
      final Map<int, TradeField> mapped =
          (aliases ?? FieldAliasTable()).mapHeader(t.header);
      if (FieldAliasTable().missingRequired(mapped).isNotEmpty) {
        // Not a trade table (a nav bar, a summary block) — keep looking.
        continue;
      }
      for (int i = 0; i < t.rows.length; i++) {
        final List<String> row = t.rows[i];
        if (row.every((String c) => c.trim().isEmpty)) continue;
        if (row.length < t.header.length) {
          issues.add(ImportIssue(
            ImportIssueCode.malformedRow,
            row: t.firstDataRow + i,
            message: 'Row ${t.firstDataRow + i} does not have as many values '
                'as the header, so it was skipped.',
          ),);
          continue;
        }
        final TradeRecord? record = mapper.mapRow(
          mapped,
          row.length > t.header.length ? row.sublist(0, t.header.length) : row,
          t.firstDataRow + i,
          issues: issues,
        );
        if (record != null) records.add(record);
      }
      // The first readable trade table wins; statements repeat themselves per section.
      if (records.isNotEmpty) {
        return ParseOutcome(records: records, issues: issues);
      }
    }

    if (records.isEmpty) {
      throw TradeImportException.of(
        ImportIssueCode.missingRequiredColumns,
        'That HTML file has no table with trade ID, symbol, direction and '
        'volume columns.',
        issues: issues,
      );
    }
    return ParseOutcome(records: records, issues: issues);
  }
/// The table body, tolerant of an unclosed `<table>`: the body ends at `</table>` or EOF.
  static final RegExp _tableRx = RegExp(
    r'<table[^>]*>([\s\S]*?)(?:</table>|(?=<table)|$)',
    caseSensitive: false,
  );

  /// All tables in the document, as a list of rows of cell text.
  static List<List<List<String>>> _tables(String html) {
    final List<List<List<String>>> out = <List<List<String>>>[];
    for (final RegExpMatch m in _tableRx.allMatches(html)) {
      final List<List<String>> rows = _rows(m.group(1) ?? '');
      if (rows.isNotEmpty) out.add(rows);
    }
    return out;
  }

  static final RegExp _rowRx = RegExp(
    // Tolerates an unclosed <tr>: the body ends at </tr>, at the next <tr>, or at EOF. Real
    // broker statements are full of missing close tags, and losing every trade over a </tr>
    // would be a bad trade-off.
    r'<tr[^>]*>([\s\S]*?)(?:</tr>|(?=<tr)|$)',
    caseSensitive: false,
  );

  static final RegExp _cellRx = RegExp(
    r'<t[hd][^>]*>([\s\S]*?)(?:</t[hd]>|(?=<t[hd])|$)',
    caseSensitive: false,
  );

  /// Rows of a table's inner HTML.
  static List<List<String>> _rows(String tableHtml) {
    final List<List<String>> rows = <List<String>>[];
    for (final RegExpMatch r in _rowRx.allMatches(tableHtml)) {
      final String inner = r.group(1) ?? '';
      final List<String> cells = <String>[];
      for (final RegExpMatch c in _cellRx.allMatches(inner)) {
        cells.add(_text(c.group(1) ?? ''));
      }
      // A row with no cells is layout markup (`<tr></tr>`), not data.
      if (cells.isNotEmpty) rows.add(cells);
    }
    return rows;
  }

  /// Cell text: tags stripped, entities decoded, whitespace collapsed.
  static String _text(String html) {
    String s = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
    s = _decodeEntities(s);
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _decodeEntities(String s) {
    const Map<String, String> named = <String, String>{
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
      '&euro;': '€',
      '&pound;': '£',
    };
    String out = s;
    named.forEach((String k, String v) {
      out = out.replaceAll(k, v).replaceAll(k.toUpperCase(), v);
    });
    // Numeric entities, decimal and hex.
    out = out.replaceAllMapped(
      RegExp('&#(x?)([0-9a-fA-F]+);'),
      (Match m) {
        final int code = m.group(1)!.isEmpty
            ? int.parse(m.group(2)!, radix: 10)
            : int.parse(m.group(2)!, radix: 16);
        if (code < 32 || code > 0x10FFFF) return '';
        return String.fromCharCode(code);
      },
    );
    return out;
  }

  /// Splits a table into a header row and data rows.
  ///
  /// A statement may open with a title or summary line, so the header is the first row that
  /// actually names recognised fields — the same forgiveness the CSV parser shows.
  static _Table _splitHeader(List<List<String>> rows) {
    for (int i = 0; i < rows.length; i++) {
      final Map<int, TradeField> mapped = FieldAliasTable().mapHeader(rows[i]);
      if (FieldAliasTable().missingRequired(mapped).isEmpty) {
        return _Table(
          header: rows[i],
          rows: rows.sublist(i + 1),
          // Row numbers in messages refer to the data rows that follow the header.
          firstDataRow: i + 2,
        );
      }
    }
    return _Table(
      header: rows.first,
      rows: const <List<String>>[],
      firstDataRow: 1,
    );
  }
}

class _Table {
  const _Table({
    required this.header,
    required this.rows,
    required this.firstDataRow,
  });

  final List<String> header;
  final List<List<String>> rows;

  /// 1-based index of the first data row in the source document.
  final int firstDataRow;
}