import 'data/trade_file_parser.dart';
import 'data/trade_import_repository.dart';
import 'data/trade_parser_registry.dart';
import 'domain/import_issue.dart';
import 'domain/trade_record.dart';

/// Outcome of an import, in domain terms only.
///
/// The UI renders this and nothing else: no CSV rows, no HTML nodes, no broker column names.
/// [imported] and [skipped] make the "we dropped 3 of 400 rows" case impossible to hide.
class TradeImportResult {
  const TradeImportResult({
    required this.accountId,
    required this.parsed,
    required this.imported,
    required this.issues,
    required this.duplicateCount,
    this.strategy = DuplicateStrategy.skipExisting,
  });

  /// The account the trades were written to.
  final String accountId;

  /// Records the parser produced, after in-file dedupe.
  final List<TradeRecord> parsed;

  /// Records actually written. Anything skipped because of [DuplicateStrategy] is excluded.
  final List<TradeRecord> imported;

  /// Row-level problems (bad date, unknown direction, ...). Trader-safe copy.
  final List<ImportIssue> issues;

  /// How many parsed records were not written because their identifier already existed.
  final int duplicateCount;

  final DuplicateStrategy strategy;

  /// Rows the parser dropped, whether or not the import succeeded.
  int get skipped => issues.length;

  bool get isPartial => issues.isNotEmpty || duplicateCount > 0;

  /// One-line summary for the import sheet.
  String get summary {
    final StringBuffer b = StringBuffer()
      ..write('Imported ${imported.length} trade${imported.length == 1 ? '' : 's'}');
    if (duplicateCount > 0) b.write(', $duplicateCount already in this account');
    if (issues.isNotEmpty) {
      b.write(', ${issues.length} row${issues.length == 1 ? '' : 's'} skipped');
    }
    return b.toString();
  }
}

/// Orchestrates parse -> normalize -> validate -> dedupe -> persist.
///
/// Deliberately has no broker, Supabase or MetaAPI knowledge: it is handed a registry and a
/// repository. Every failure it raises is a [TradeImportException] whose [message] is safe to
/// render.
class TradeImportService {
  const TradeImportService({
    required TradeParserRegistry registry,
    required TradeImportRepository repository,
  })  : _registry = registry,
        _repository = repository;

  final TradeParserRegistry _registry;
  final TradeImportRepository _repository;

  /// Imports [source] into [accountId].
  ///
  /// In-file duplicates (the same identifier twice) are always an error: a statement that
  /// repeats a ticket is ambiguous, and picking one arbitrarily would make the import
  /// non-deterministic. Cross-file duplicates go through [strategy].
  Future<TradeImportResult> importFile(
    ImportSource source, {
    required String accountId,
    DuplicateStrategy strategy = DuplicateStrategy.skipExisting,
  }) async {
    final ParseOutcome outcome = _registry.parse(source);
    final List<ImportIssue> issues = List<ImportIssue>.of(outcome.issues);

    final List<TradeRecord> deduped = _dedupeInFile(outcome.records, issues);
    if (deduped.isEmpty) {
      throw TradeImportException.of(
        ImportIssueCode.emptyFile,
        'No trades could be read from that file.',
        issues: issues,
      );
    }

    final Set<String> existing =
        await _repository.existingExternalIds(accountId);
    if (strategy == DuplicateStrategy.fail) {
      final List<TradeRecord> clashes = deduped
          .where((TradeRecord r) => existing.contains(r.externalId))
          .toList();
      if (clashes.isNotEmpty) {
        throw TradeImportException.of(
          ImportIssueCode.duplicateTradeIdInAccount,
          '${clashes.length} of these trades are already in the account. '
          'Nothing was imported.',
          issues: <ImportIssue>[
            ImportIssue(
              ImportIssueCode.duplicateTradeIdInAccount,
              message: 'Trade ${clashes.first.externalId} is already in this '
                  'account.',
            ),
          ],
        );
      }
    }

    final int before = deduped.length;
    final List<TradeRecord> toWrite = strategy == DuplicateStrategy.skipExisting
        ? deduped
            .where((TradeRecord r) => !existing.contains(r.externalId))
            .toList()
        : deduped;

    if (toWrite.isEmpty) {
      return TradeImportResult(
        accountId: accountId,
        parsed: deduped,
        imported: const <TradeRecord>[],
        issues: issues,
        duplicateCount: before,
        strategy: strategy,
      );
    }

    final int written = await _save(
      accountId,
      toWrite,
      strategy: strategy,
    );

    return TradeImportResult(
      accountId: accountId,
      parsed: deduped,
      // Trust what was written, not what we offered: the repository is the authority on the
      // duplicate decision.
      imported: strategy == DuplicateStrategy.skipExisting ||
              strategy == DuplicateStrategy.allowDuplicates
          ? toWrite
          : deduped.take(written).toList(),
      issues: issues,
      duplicateCount: strategy == DuplicateStrategy.skipExisting
          ? before - toWrite.length
          : 0,
      strategy: strategy,
    );
  }

  /// Saves through the repository, mapping any backend failure onto trader-safe copy.
  ///
  /// A Postgres error text names tables, constraints and SQLSTATE codes; none of that may be
  /// shown to a trader, but it is retained in [TradeImportException.detail] for diagnostics.
  /// [TradeImportException] from the repository is a deliberate policy decision (duplicate
  /// `fail`) and is passed through unchanged.
  Future<int> _save(
    String accountId,
    List<TradeRecord> records, {
    required DuplicateStrategy strategy,
  }) async {
    try {
      return await _repository.saveTrades(
        accountId,
        records,
        strategy: strategy,
      );
    } on TradeImportException {
      rethrow;
    } catch (e) {
      throw TradeImportException.of(
        ImportIssueCode.unreadableFile,
        'Your trades could not be saved. Check your connection and try again.',
        cause: e,
      );
    }
  }

  /// Keeps the first occurrence of each identifier and reports the rest.
  ///
  /// First-wins is deterministic and matches the "same statement imported twice" case, where
  /// the two copies are identical anyway.
  static List<TradeRecord> _dedupeInFile(
    List<TradeRecord> records,
    List<ImportIssue> issues,
  ) {
    final Set<String> seen = <String>{};
    final List<TradeRecord> out = <TradeRecord>[];
    for (final TradeRecord r in records) {
      if (seen.add(r.externalId)) {
        out.add(r);
      } else {
        issues.add(ImportIssue(
          ImportIssueCode.duplicateTradeId,
          field: 'trade ID',
          message: 'Trade ${r.externalId} appears more than once in this file; '
              'only the first was kept.',
        ),);
      }
    }
    return out;
  }
}