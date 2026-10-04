import 'package:csv/csv.dart';

import '../domain/import_issue.dart';
import '../domain/trade_record.dart';
import 'field_aliases.dart';
import 'trade_file_parser.dart';

/// CSV trade-history parser.
///
/// RFC-4180 quoting is handled by the `csv` package (already a dependency — no new packages
/// for this feature). Everything the package can get wrong is caught and re-thrown as a
/// [TradeImportException] with copy the trader can act on; the package's own message is kept
/// only in [TradeImportException.detail].
class CsvTradeParser extends TradeFileParser {
  const CsvTradeParser({super.aliases, this.delimiter = ','});

  /// Field separator. Exposed so a semicolon-delimited European export can be read by
  /// constructing the parser — not by changing any other layer.
  final String delimiter;

  @override
  String get formatName => 'CSV';

  @override
  bool canParse(ImportSource source) {
    // Content is sniffed FIRST: a statement saved as `.txt` is still HTML, and feeding it to
    // the CSV parser would produce garbage rather than a clean "unsupported" error.
    if (_looksLikeHtml(source.content)) return false;
    if (source.extension == 'csv') return true;
    // No usable extension: claim it so the CSV error is specific rather than "unsupported".
    return source.extension.isEmpty;
  }

  static bool _looksLikeHtml(String content) {
    final String head = content
        .substring(0, content.length < 512 ? content.length : 512)
        .toLowerCase();
    return head.contains('<html') ||
        head.contains('<table') ||
        head.contains('<!doctype');
  }

  @override
  ParseOutcome parse(ImportSource source) {
    if (source.isBlank) {
      throw TradeImportException.of(
        ImportIssueCode.emptyFile,
        'That file is empty. Export your trade history and try again.',
      );
    }

    final List<List<dynamic>> table = _decode(source.content);

    // Leading junk before the real header (an export note, a title) is common, so look for the
    // first row that actually names the required fields rather than failing the whole file.
    final FieldAliasTable fields = aliases ?? FieldAliasTable();
    int headerIndex = 0;
    Map<int, TradeField> columns = const <int, TradeField>{};
    while (headerIndex < table.length) {
      columns = fields.mapHeader(_cells(table[headerIndex]));
      if (fields.missingRequired(columns).isEmpty) break;
      headerIndex++;
    }
    if (headerIndex >= table.length || columns.isEmpty) {
      throw TradeImportException.of(
        ImportIssueCode.missingRequiredColumns,
        'No header row with trade ID, symbol, direction and volume was found in '
        'this CSV.',
      );
    }
    // `requireHeader` produces the trader-safe "missing columns" copy for a header that has
    // the fields but not all of them.
    final List<String> headerCells = _cells(table[headerIndex]);
    final TradeRowMapper mapper = TradeRowMapper(fields);
    final Map<int, TradeField> mapped = mapper.requireHeader(headerCells);
    final int width = headerCells.length;
    final List<ImportIssue> issues = <ImportIssue>[];
    final List<TradeRecord> records = <TradeRecord>[];

    for (int i = headerIndex + 1; i < table.length; i++) {
      final List<String> row = _cells(table[i]);
      if (row.every((String c) => c.trim().isEmpty)) continue; // blank line

      // A short row is dropped here rather than padded: a statement with a missing value in
      // the middle would otherwise shift every column after it and import wrong prices.
      if (row.length < width) {
        issues.add(ImportIssue(
          ImportIssueCode.malformedRow,
          row: i + 1,
          message: 'Row ${i + 1} does not have as many values as the header, '
              'so it was skipped.',
        ),);
        continue;
      }

      final TradeRecord? record = mapper.mapRow(
        _restrict(mapped, width),
        // Extra trailing cells are ignored: a trailing "Balance" column is not a fault.
        row.length > width ? row.sublist(0, width) : row,
        i + 1,
        issues: issues,
      );
      if (record != null) records.add(record);
    }

    if (records.isEmpty) {
      // Every data row was rejected. Surface the per-row reasons when we have them — "the file
      // is empty" would send the trader hunting for a missing export instead of the bad data.
      throw TradeImportException.of(
        issues.isEmpty ? ImportIssueCode.emptyFile : ImportIssueCode.malformedRow,
        issues.isEmpty
            ? 'No trades could be read from that CSV.'
            : 'None of the ${issues.length} rows in that CSV could be read. '
                'Check the values and export it again.',
        issues: issues,
      );
    }
    return ParseOutcome(records: records, issues: issues);
  }

  /// Decodes the text, converting any package-level failure into our own vocabulary.
  List<List<dynamic>> _decode(String content) {
    final CsvToListConverter converter = CsvToListConverter(
      fieldDelimiter: delimiter,
      // Strings, not numbers: we want our own coercion (and our own error copy) to run, not
      // the package's silent num.parse.
      shouldParseNumbers: false,
      eol: '\n',
      // Reject unbalanced quotes instead of guessing.
      allowInvalid: false,
    );
    try {
      final List<List<dynamic>> rows = converter.convert(content);
      return rows
          .where((List<dynamic> r) => r.isNotEmpty)
          .toList(growable: false);
    } on FormatException catch (e) {
      throw TradeImportException.of(
        ImportIssueCode.malformedFile,
        'That CSV could not be read. Check for an unclosed quote or a stray '
        'delimiter and export it again.',
        cause: e,
      );
    } catch (e) {
      // Deliberately broad: no parser exception text may reach the trader.
      throw TradeImportException.of(
        ImportIssueCode.malformedFile,
        'That CSV could not be read. Check the file and try again.',
        cause: e,
      );
    }
  }

  static List<String> _cells(List<dynamic> row) =>
      row.map((dynamic c) => c?.toString().trim() ?? '').toList();

  /// Drops column mappings beyond the header width.
  static Map<int, TradeField> _restrict(Map<int, TradeField> columns, int width) {
    final Map<int, TradeField> out = <int, TradeField>{};
    columns.forEach((int i, TradeField f) {
      if (i < width) out[i] = f;
    });
    return out;
  }
}