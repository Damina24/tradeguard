/// Why an import was refused, or why a row was dropped.
///
/// Kept as an enum rather than free text so the UI can branch (e.g. offer "skip duplicates"
/// only for [duplicateTradeId]) and so tests can assert on a cause instead of a message.
enum ImportIssueCode {
  /// The file parsed, but held no trade rows at all.
  emptyFile,

  /// Bytes were not valid CSV / the document was not valid trade-history HTML.
  malformedFile,

  /// No recognizable trade table in the HTML.
  unsupportedFileStructure,

  /// One or more columns the importer requires are absent.
  missingRequiredColumns,

  /// A required value was blank.
  missingRequiredField,

  /// A date/timestamp could not be interpreted.
  invalidDate,

  /// A numeric value was not a number.
  invalidNumber,

  /// Volume was zero, negative or implausibly large.
  invalidVolume,

  /// A direction was present but not a value we accept.
  unsupportedDirection,

  /// A row had the wrong number of cells for its header.
  malformedRow,

  /// Two rows in the same file carried the same trade identifier.
  duplicateTradeId,

  /// The identifier already exists in the destination account.
  duplicateTradeIdInAccount,

  /// File could not be read.
  unreadableFile,
}

/// One problem, in trader-safe words.
///
/// [detail] is the raw parser/provider text kept ONLY for logs and tests. It is never
/// rendered, because a parser exception can quote the whole offending line of the user's
/// statement.
class ImportIssue {
  const ImportIssue(
    this.code, {
    this.row,
    this.field,
    required this.message,
    this.detail,
  });

  /// 1-based row number within the source file, or null for file-level problems.
  final int? row;

  /// Canonical field name from the domain layer (e.g. `volumeLots`), never a broker column.
  final String? field;

  /// Safe to show the trader. Generated from [code] + [row] + [field] by the producers.
  final String message;

  final ImportIssueCode code;

  /// Raw technical text. Diagnostics and tests only.
  final String? detail;

  /// Single-line rendering for logs — deliberately includes [detail] so a support log keeps
  /// the original error, while the UI uses [message] alone.
  @override
  String toString() {
    final StringBuffer b = StringBuffer(code.name);
    if (row != null) b.write(' row $row');
    if (field != null) b.write(' $field');
    b.write(': $message');
    final String? d = detail;
    if (d != null) b.write(' [$d]');
    return b.toString();
  }
}

/// Raised when an import cannot proceed.
///
/// The [message] is always trader-safe copy; the underlying parser exception is kept in
/// [detail] / [issues] and never reaches the UI. Mirrors `BrokerConnectException` and
/// `SocialAuthException` so the app has one failure pattern.
class TradeImportException implements Exception {
  const TradeImportException(
    this.code,
    this.message, {
    this.issues = const <ImportIssue>[],
    this.detail,
  });

  /// Convenience for a whole-file failure.
  factory TradeImportException.of(
    ImportIssueCode code,
    String message, {
    Object? cause,
    List<ImportIssue> issues = const <ImportIssue>[],
  }) =>
      TradeImportException(
        code,
        message,
        issues: issues,
        detail: cause?.toString(),
      );

  final ImportIssueCode code;

  /// Safe to render.
  final String message;

  /// Row-level problems, if any. Empty for a single whole-file failure.
  final List<ImportIssue> issues;

  /// Raw technical text for diagnostics and tests only.
  final String? detail;

  @override
  String toString() => 'TradeImportException(${code.name}): $message';
}