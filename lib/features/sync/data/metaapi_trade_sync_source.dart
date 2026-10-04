import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/trade_sync_source.dart';

/// Live MetaAPI deal reader.
///
/// The token lives only in this class's caller-supplied [token] and is used for exactly one
/// header on exactly one request. It is never logged, never returned, never persisted, and
/// never travels to the client: in the deployed app this source runs *inside* the
/// `sync-trades` Edge Function, not in the Flutter app.
///
/// Provider status codes are translated into [TradeSyncFailure]s here, so the service above
/// never sees an `http.ClientException` and the UI never sees a MetaAPI error body.
class MetaApiTradeSyncSource implements TradeSyncSource {
  MetaApiTradeSyncSource({
    required this.token,
    http.Client? client,
    this.baseUrl = defaultBaseUrl,
  }) : _client = client ?? http.Client();

  /// MetaAPI's REST host.
  static const String defaultBaseUrl = 'https://api.metavantage.com';

  /// Read from the server-side secret store. Empty means "not configured".
  final String token;

  final http.Client _client;
  final String baseUrl;

  @override
  bool get isStubbed => token.isEmpty;

  @override
  Future<TradeSyncPage> fetchTrades({
    required String providerAccountId,
    DateTime? since,
    String? cursor,
    int limit = 100,
  }) async {
    if (token.isEmpty) {
      throw const TradeSyncException(
        TradeSyncFailure.notConfigured,
        'Broker sync is not configured for this build.',
      );
    }

    final Uri uri = Uri.parse('$baseUrl/v3/accounts/$providerAccountId/deals')
        .replace(
      queryParameters: <String, String>{
        // Capped client-side too: a caller cannot ask for the whole history in one page.
        'limit': '${limit.clamp(1, 500)}',
        if (since != null) 'from': since.toUtc().toIso8601String(),
        if (cursor != null) 'cursor': cursor,
      },
    );

    late final http.Response res;
    try {
      res = await _client.get(uri, headers: <String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },);
    } catch (e) {
      throw TradeSyncException(
        TradeSyncFailure.network,
        'Could not reach your broker to sync trades.',
        detail: e.toString(),
      );
    }

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const TradeSyncException(
        TradeSyncFailure.authFailed,
        'Your broker connection expired. Reconnect the account.',
      );
    }
    if (res.statusCode == 429) {
      throw TradeSyncException(
        TradeSyncFailure.rateLimited,
        'Your broker is busy. Try again shortly.',
        retryAfter: _retryAfter(res),
      );
    }
    if (res.statusCode >= 500) {
      throw TradeSyncException(
        TradeSyncFailure.network,
        'Your broker is temporarily unavailable.',
        detail: 'status ${res.statusCode}',
      );
    }
    if (res.statusCode != 200) {
      throw TradeSyncException(
        TradeSyncFailure.malformedResponse,
        'Your broker rejected the sync request.',
        detail: 'status ${res.statusCode}',
      );
    }

    return _parse(res.body, cursor);
  }

  /// Turns a MetaAPI body into a page, or raises [TradeSyncFailure.malformedResponse].
  ///
  /// Split out and pure so the parsing rules are testable with no HTTP client.
  TradeSyncPage parse(String body, String? cursor) => _parse(body, cursor);

  static TradeSyncPage _parse(String body, String? cursor) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (e) {
      throw TradeSyncException(
        TradeSyncFailure.malformedResponse,
        'Your broker sent something we could not read.',
        detail: e.toString(),
      );
    }
    // MetaAPI returns a bare array or {deals: [...]}.
    final List<dynamic> raw = switch (decoded) {
      List<dynamic> l => l,
      Map<String, dynamic> m when m['deals'] is List<dynamic> =>
        m['deals'] as List<dynamic>,
      Map<String, dynamic> m when m['trades'] is List<dynamic> =>
        m['trades'] as List<dynamic>,
      _ => <dynamic>[],
    };

    if (raw.isEmpty) return const TradeSyncPage.empty();

    final List<Map<String, dynamic>> deals = <Map<String, dynamic>>[];
    for (final dynamic d in raw) {
      // A non-object entry is dropped rather than failing the page: one odd record must not
      // cost the trader the rest of the window.
      if (d is Map<String, dynamic>) deals.add(d);
      if (d is Map && d is! Map<String, dynamic>) {
        deals.add(Map<String, dynamic>.from(d));
      }
    }
    if (deals.isEmpty) {
      throw const TradeSyncException(
        TradeSyncFailure.malformedResponse,
        'Your broker sent something we could not read.',
      );
    }

    // MetaAPI is offset/limit based rather than cursor based, so the next offset is derived
    // from what we already served.
    final int next = (int.tryParse(cursor ?? '') ?? 0) + deals.length;
    return TradeSyncPage(deals: deals, nextCursor: '$next', hasMore: true);
  }

  static Duration? _retryAfter(http.Response res) {
    final String? header = res.headers['retry-after'];
    final int? seconds = header == null ? null : int.tryParse(header);
    if (seconds == null) return const Duration(seconds: 60);
    return Duration(seconds: seconds.clamp(1, 3600));
  }
}