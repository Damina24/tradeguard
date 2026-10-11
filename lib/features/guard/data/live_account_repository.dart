import '../../../core/models/live_account.dart';

/// Live account reads: balance, equity, connection health and open positions.
///
/// Kept separate from [AccountRepository] on purpose. The persisted account record
/// carries the prop-firm rules and the *last known* equity the guard math runs on;
/// this seam is the *right now* read the dashboard shows. A slow or failed live
/// read must never touch the guard's drawdown/daily-loss numbers, so the two never
/// share a code path.
abstract class LiveAccountRepository {
  /// The live snapshot for one account, or throws [LiveAccountException] when the
  /// broker could not be reached. Never fabricates numbers.
  Future<LiveAccountData> fetchLive(String accountId);
}

/// A live read that failed. [message] is trader-safe and carries no broker text.
class LiveAccountException implements Exception {
  const LiveAccountException(this.message);
  final String message;

  @override
  String toString() => 'LiveAccountException: $message';
}
