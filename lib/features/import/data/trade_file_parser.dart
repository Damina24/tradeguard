import '../../../../core/models/trade.dart';
import '../domain/import_issue.dart';
import '../domain/trade_record.dart';
import 'field_aliases.dart';
import 'value_normalizer.dart';

/// The bytes handed to a parser, plus whatever we know about where they came from.
///
/// [content] is text rather than a path so the whole importer is unit-testable without a
/// filesystem, a plugin channel or a real download.
class ImportSource {
  const ImportSource({
    required this.content,
    this.fileName = '',
    this.mimeType,
  });

  final String content;
  final String fileName;
  final String? mimeType;

  /// Extension used to pick a parser. Lower-cased, without the dot.
  String get extension {
    final int dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  }

  bool get isBlank => content.trim().isEmpty;
}

/// Result of a successful parse: normalized records plus any rows that were dropped.
///
/// Dropped rows never abort the import — one bad line in a 400-row statement must not cost the
/// trader the other 399. The caller decides whether a partial import is acceptable.
class ParseOutcome {
  const ParseOutcome({required this.records, this.issues = const <ImportIssue>[]});

  final List<TradeRecord> records;
  final List<ImportIssue> issues;
}

/// A file format the importer understands.
///
/// Implement this to add a broker or export format. [parse] must:
///
/// * throw [TradeImportException] only for whole-file failures (empty, malformed, missing
///   columns), never carrying a raw parser message to the user;
/// * record row-level problems in [ParseOutcome.issues] and carry on;
/// * return normalized [TradeRecord]s, so nothing downstream sees a CSV row or HTML node.
abstract class TradeFileParser {
  const TradeFileParser({this.aliases});

  /// Broker/export vocabulary for this format.
  final FieldAliasTable? aliases;

  /// Human name of the format, used in copy and tests.
  String get formatName;

  /// Whether this parser claims [source].
  bool canParse(ImportSource source);

  /// Reads the file into normalized records.
  ParseOutcome parse(ImportSource source);
}

/// Shared header mapping + row validation.
///
/// Both parsers funnel through here, which is what guarantees a CSV import and an HTML import
/// of the same trades produce identical [TradeRecord]s.
class TradeRowMapper {
  const TradeRowMapper(this.aliases);

  final FieldAliasTable aliases;

  /// Maps a header, or throws when a required column is absent.
  Map<int, TradeField> requireHeader(List<String> header) {
    final Map<int, TradeField> columns = aliases.mapHeader(header);
    final List<TradeField> missing = aliases.missingRequired(columns);
    if (missing.isNotEmpty) {
      throw TradeImportException.of(
        ImportIssueCode.missingRequiredColumns,
        'This file is missing required columns: '
        '${missing.map(FieldAliasTable.label).join(', ')}.',
      );
    }
    return columns;
  }

  /// Converts one row, or records why it could not be used.
  ///
  /// [rowNumber] is the 1-based line in the source file, so error copy points at the right
  /// line in the trader's spreadsheet.
  TradeRecord? mapRow(
    Map<int, TradeField> columns,
    List<String> row,
    int rowNumber, {
    required List<ImportIssue> issues,
  }) {
    String? raw(TradeField field) {
      for (final MapEntry<int, TradeField> e in columns.entries) {
        if (e.value == field && e.key < row.length) return row[e.key];
      }
      return null;
    }

    // Fewer cells than the header means we cannot trust this row at all.
    if (row.length < columns.length) {
      issues.add(ImportIssue(
        ImportIssueCode.malformedRow,
        row: rowNumber,
        message: 'Row $rowNumber does not have as many values as the header, '
            'so it was skipped.',
      ),);
      return null;
    }

    final String id = text(raw(TradeField.externalId)) ?? '';
    if (id.isEmpty) {
      issues.add(_missing(rowNumber, 'trade ID'));
      return null;
    }

    final Coerced<String> sym = ValueNormalizer.symbol(raw(TradeField.symbol));
    if (sym.blank) {
      issues.add(_missing(rowNumber, 'symbol'));
      return null;
    }
    if (!sym.isValid) {
      issues.add(ImportIssue(
        ImportIssueCode.invalidNumber,
        row: rowNumber,
        field: 'symbol',
        message: 'The symbol in row $rowNumber could not be read, so that row '
            'was skipped.',
      ),);
      return null;
    }

    final Coerced<TradeDirection> dir =
        ValueNormalizer.direction(raw(TradeField.direction));
    if (dir.blank) {
      issues.add(_missing(rowNumber, 'direction'));
      return null;
    }
    if (!dir.isValid) {
      issues.add(ImportIssue(
        ImportIssueCode.unsupportedDirection,
        row: rowNumber,
        field: 'direction',
        message: 'The direction in row $rowNumber is not buy or sell, so that '
            'row was skipped.',
      ),);
      return null;
    }

    final Coerced<double> vol = ValueNormalizer.volume(raw(TradeField.volume));
    if (vol.blank) {
      issues.add(_missing(rowNumber, 'volume'));
      return null;
    }
    if (!vol.isValid) {
      issues.add(ImportIssue(
        ImportIssueCode.invalidVolume,
        row: rowNumber,
        field: 'volume',
        message: 'The volume in row $rowNumber is not a usable size '
            '(${vol.reason}), so that row was skipped.',
      ),);
      return null;
    }

    final int issueCountBeforeOptionals = issues.length;
    final double? entry =
        _number(raw(TradeField.entryPrice), rowNumber, 'entry price', issues);
    final double? exit =
        _number(raw(TradeField.exitPrice), rowNumber, 'exit price', issues);
    final double? sl =
        _number(raw(TradeField.stopLoss), rowNumber, 'stop loss', issues);
    final double? tp =
        _number(raw(TradeField.takeProfit), rowNumber, 'take profit', issues);
    final double? profit = _number(raw(TradeField.profit), rowNumber, 'profit', issues);
    final double? commission =
        _number(raw(TradeField.commission), rowNumber, 'commission', issues);
    final double? swap = _number(raw(TradeField.swap), rowNumber, 'swap', issues);
    final DateTime? open =
        _date(raw(TradeField.openTime), rowNumber, 'open time', issues);
    final DateTime? close =
        _date(raw(TradeField.closeTime), rowNumber, 'close time', issues);

    // An optional field that was PRESENT but unreadable invalidates the row. Keeping it and
    // silently nulling the price would import a trade with a wrong stop or take profit, which
    // is worse than skipping it: R-multiple and the journal would be wrong, not merely empty.
    if (issues.length != issueCountBeforeOptionals) return null;

    return TradeRecord(
      externalId: id,
      symbol: sym.value!,
      direction: dir.value!,
      volumeLots: vol.value!,
      entryPrice: entry,
      exitPrice: exit,
      stopLoss: sl,
      takeProfit: tp,
      openTime: open,
      closeTime: close,
      profit: profit ?? 0,
      commission: commission ?? 0,
      swap: swap ?? 0,
      currency: text(raw(TradeField.currency)),
      broker: text(raw(TradeField.broker)),
      accountNumber: text(raw(TradeField.accountNumber)),
    );
  }
static ImportIssue _missing(int row, String label) => ImportIssue(
        ImportIssueCode.missingRequiredField,
        row: row,
        field: label,
        message: 'Row $row is missing its $label, so it was skipped.',
      );

  /// Blank is fine (the column may legitimately be absent); present-but-wrong is not.
  double? _number(
    String? raw,
    int row,
    String label,
    List<ImportIssue> issues,
  ) {
    final Coerced<double> n = ValueNormalizer.number(raw);
    if (n.blank) return null;
    if (!n.isValid) {
      issues.add(ImportIssue(
        ImportIssueCode.invalidNumber,
        row: row,
        field: label,
        message: 'The $label in row $row is not a number, so that row was '
            'skipped.',
      ),);
      return null;
    }
    return n.value;
  }

  DateTime? _date(
    String? raw,
    int row,
    String label,
    List<ImportIssue> issues,
  ) {
    final Coerced<DateTime> d = ValueNormalizer.date(raw);
    if (d.blank) return null;
    if (!d.isValid) {
      issues.add(ImportIssue(
        ImportIssueCode.invalidDate,
        row: row,
        field: label,
        message: 'The $label in row $row is not a valid date, so that row was '
            'skipped.',
      ),);
      return null;
    }
    return d.value;
  }

  static String? text(String? raw) {
    final String s = (raw ?? '').trim();
    return s.isEmpty ? null : s;
  }
}