import '../domain/pattern_row.dart';
import 'pattern_repository.dart';

/// Offline `v_patterns`, seeded with literal rows.
///
/// The fixtures are **pre-grouped**, exactly as Postgres would return them. They
/// are deliberately NOT computed by aggregating `MockData.trades()` in Dart:
/// that would be a second implementation of the view's SQL, and if the two ever
/// disagreed the app would show a pattern the database does not support. Writing
/// the rows out means the mock exercises the same contract the live view does.
///
/// The seed is arranged to be interesting rather than uniform: London is losing
/// on XAUUSD, one Friday group is losing badly, and the New York groups are
/// carrying the account. That gives the leaks screen something real to find
/// without any backend.
class MockPatternRepository implements PatternRepository {
  MockPatternRepository({this.rows = defaultRows});

  /// Overridable so a test can drive empty / sparse / hostile datasets without a
  /// backend.
  final List<PatternRow> rows;

  /// The demo identity used by `MockAuthRepository`. Fixtures are stamped with it
  /// so the account-isolation assertions have something real to check.
  static const String userId = 'demo-user';

  @override
  Future<List<PatternRow>> fetchPatterns() async =>
      List<PatternRow>.unmodifiable(rows);

  /// Pre-grouped `v_patterns` rows for the demo journal.
  ///
  /// Columns per row: symbol, session, dow (0=Sun), hour, pnl, n, win_rate.
  static const List<PatternRow> defaultRows = <PatternRow>[
    // XAUUSD is the problem pair, and London is where it goes wrong.
    PatternRow(
      userId: userId,
      symbol: 'XAUUSD',
      session: 'london',
      dayOfWeek: 1,
      hour: 8,
      pnl: -1420.50,
      trades: 24,
      winRate: 0.29,
    ),
    PatternRow(
      userId: userId,
      symbol: 'XAUUSD',
      session: 'newyork',
      dayOfWeek: 2,
      hour: 14,
      pnl: 2180.00,
      trades: 19,
      winRate: 0.63,
    ),
    PatternRow(
      userId: userId,
      symbol: 'XAUUSD',
      session: 'newyork',
      dayOfWeek: 3,
      hour: 15,
      pnl: 940.25,
      trades: 11,
      winRate: 0.55,
    ),
    PatternRow(
      userId: userId,
      symbol: 'XAUUSD',
      session: null,
      dayOfWeek: 5,
      hour: 22,
      pnl: -680.00,
      trades: 7,
      winRate: 0.14,
    ),
    // EURUSD is clean, and stays clean — the screen must show something healthy.
    PatternRow(
      userId: userId,
      symbol: 'EURUSD',
      session: 'london',
      dayOfWeek: 1,
      hour: 9,
      pnl: 1120.00,
      trades: 22,
      winRate: 0.68,
    ),
    PatternRow(
      userId: userId,
      symbol: 'EURUSD',
      session: 'newyork',
      dayOfWeek: 4,
      hour: 13,
      pnl: 480.75,
      trades: 9,
      winRate: 0.56,
    ),
    PatternRow(
      userId: userId,
      symbol: 'GBPUSD',
      session: 'london',
      dayOfWeek: 2,
      hour: 10,
      pnl: -310.40,
      trades: 12,
      winRate: 0.42,
    ),
    PatternRow(
      userId: userId,
      symbol: 'GBPUSD',
      session: 'asia',
      dayOfWeek: 3,
      hour: 3,
      pnl: 265.00,
      trades: 6,
      winRate: 0.50,
    ),
    PatternRow(
      userId: userId,
      symbol: 'US30',
      session: 'newyork',
      dayOfWeek: 2,
      hour: 15,
      pnl: -505.60,
      trades: 4,
      // Under the reporting floor, so it must never surface as a leak even though
      // it is losing. This is the single-trade-anecdote guard, live.
      winRate: 0.25,
    ),
    PatternRow(
      userId: userId,
      symbol: 'US30',
      session: 'newyork',
      dayOfWeek: 5,
      hour: 16,
      pnl: 890.30,
      trades: 8,
      winRate: 0.63,
    ),
  ];
}