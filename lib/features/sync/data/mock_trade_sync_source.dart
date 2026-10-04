import '../domain/trade_sync_source.dart';

/// Deterministic offline provider, so the whole sync flow runs with no MetaAPI credentials.
///
/// Mock mode is the app's default (see `AppConfig.useMock`), so without this the sync feature
/// would be unusable until a provider is configured — the same reason `MockTradeRepository`
/// exists.
///
/// Every failure mode the real source can produce is injectable, which is how the tests
/// exercise auth failure, rate limiting and network errors without a network.
class MockTradeSyncSource implements TradeSyncSource {
  MockTradeSyncSource({List<Map<String, dynamic>>? deals}) : _deals = deals ?? seed();

  final List<Map<String, dynamic>> _deals;

  /// Failure to raise on the next fetch, consumed once. [TradeSyncFailure.empty] means "return
  /// nothing".
  TradeSyncFailure? failure;

  /// When [failure] is [TradeSyncFailure.rateLimited], how long to wait.
  Duration retryAfter = const Duration(seconds: 30);

  /// Pages served per call, so pagination can be exercised without a big fixture.
  int pageSize = 50;

  /// Every (since, cursor, limit) the service asked for, for assertions.
  final List<Map<String, dynamic>> calls = <Map<String, dynamic>>[];

  /// Trades handed out so far, so the mock can simulate "the broker added a trade".
  int get servedCount => _served;

  int _served = 0;

  @override
  bool get isStubbed => true;

  /// A small, believable account's history. Fixed data keeps tests deterministic.
  static List<Map<String, dynamic>> seed() => <Map<String, dynamic>>[
        <String, dynamic>{
          'ticket': '900001',
          'openTime': '2026-04-15T08:30:00Z',
          'closeTime': '2026-04-15T12:00:00Z',
          'type': 'buy',
          'volume': 0.5,
          'symbol': 'XAUUSD',
          'openPrice': 2345.10,
          'closePrice': 2351.40,
          'sl': 2340.00,
          'tp': 2351.40,
          'profit': 312.00,
          'commission': -3.50,
          'swap': -0.70,
          'currency': 'USD',
        },
        <String, dynamic>{
          'ticket': '900002',
          'openTime': '2026-04-16T09:00:00Z',
          'closeTime': '2026-04-16T11:30:00Z',
          'type': 'sell',
          'volume': 1.00,
          'symbol': 'EURUSD',
          'openPrice': 1.0850,
          'closePrice': 1.0810,
          'sl': 1.0870,
          'tp': 1.0800,
          'profit': -40.00,
          'commission': -2.40,
          'swap': -1.20,
          'currency': 'USD',
        },
        <String, dynamic>{
          'ticket': '900003',
          'openTime': '2026-04-17T07:00:00Z',
          'closeTime': '2026-04-17T09:45:00Z',
          'type': 'buy',
          'volume': 0.25,
          'symbol': 'GBPJPY',
          'openPrice': 199.40,
          'closePrice': 200.35,
          'sl': 198.90,
          'tp': 200.35,
          'profit': 23.75,
          'commission': -1.00,
          'swap': 0.00,
          'currency': 'USD',
        },
      ];

  /// Appends a deal the broker "produced" after the last sync, for incremental tests.
  void append(Map<String, dynamic> deal) => _deals.add(deal);

  /// Replaces the whole history, for "the broker restated a figure" tests.
  void replaceAll(List<Map<String, dynamic>> deals) {
    _deals
      ..clear()
      ..addAll(deals);
    _served = 0;
  }

  @override
  Future<TradeSyncPage> fetchTrades({
    required String providerAccountId,
    DateTime? since,
    String? cursor,
    int limit = 100,
  }) async {
    calls.add(<String, dynamic>{
      'providerAccountId': providerAccountId,
      'since': since?.toIso8601String(),
      'cursor': cursor,
      'limit': limit,
    });

    final TradeSyncFailure? f = failure;
    if (f != null) {
      failure = null; // consume, so a retry can succeed
      if (f == TradeSyncFailure.empty) return const TradeSyncPage.empty();
      if (f == TradeSyncFailure.rateLimited) {
        throw TradeSyncException(
          TradeSyncFailure.rateLimited,
          'Your broker is busy. Try again shortly.',
          retryAfter: retryAfter,
        );
      }
      if (f == TradeSyncFailure.authFailed) {
        throw const TradeSyncException(
          TradeSyncFailure.authFailed,
          'Your broker connection expired. Reconnect the account.',
        );
      }
      if (f == TradeSyncFailure.malformedResponse) {
        throw const TradeSyncException(
          TradeSyncFailure.malformedResponse,
          'Your broker sent something we could not read.',
          detail: 'unexpected shape: <html>502</html>',
        );
      }
      if (f == TradeSyncFailure.network) {
        throw const TradeSyncException(
          TradeSyncFailure.network,
          'Could not reach your broker.',
          detail: 'SocketException: connection refused',
        );
      }
    }

    final int start = int.tryParse(cursor ?? '') ?? 0;
    final int end = (start + (pageSize < limit ? pageSize : limit))
        .clamp(0, _deals.length);
    final List<Map<String, dynamic>> slice =
        _deals.sublist(start.clamp(0, _deals.length), end);
    _served = end;
    final bool more = end < _deals.length;
    return TradeSyncPage(
      deals: slice,
      nextCursor: more ? '$end' : null,
      hasMore: more,
    );
  }
}