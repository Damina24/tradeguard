import '../domain/import_issue.dart';
import 'csv_trade_parser.dart';
import 'html_trade_parser.dart';
import 'trade_file_parser.dart';

/// Registry of available parsers.
///
/// The application asks for "import this file" and gets back normalized records; it never
/// checks the extension and never knows that CSV and HTML exist. Adding a format is a
/// one-line change here — no screen, service or domain file needs to move.
class TradeParserRegistry {
  TradeParserRegistry({List<TradeFileParser>? parsers})
      : parsers = parsers ?? defaultParsers();

  final List<TradeFileParser> parsers;

  static List<TradeFileParser> defaultParsers() => <TradeFileParser>[
        const CsvTradeParser(),
        const HtmlTradeParser(),
      ];

  /// Picks a parser by extension, falling back to content sniffing.
  ///
  /// Throws [ImportIssueCode.unsupportedFileStructure] when nothing claims the file, with copy
  /// that names the formats we do accept.
  TradeFileParser select(ImportSource source) {
    for (final TradeFileParser p in parsers) {
      if (p.canParse(source)) return p;
    }
    throw TradeImportException.of(
      ImportIssueCode.unsupportedFileStructure,
      'That file type is not supported. Import a CSV or an HTML trade history.',
    );
  }

  /// Parse with whichever parser claims [source].
  ParseOutcome parse(ImportSource source) => select(source).parse(source);
}