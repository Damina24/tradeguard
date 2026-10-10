import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../domain/price_bar.dart';
import '../domain/price_series.dart';
import '../domain/price_series_request.dart';
import 'price_bar_repository.dart';

/// Live bar reads: `prices_cache` for the data, the `market-bars` Edge Function for the refresh.
///
/// ## Why the client never talks to TwelveData
///
/// `TWELVEDATA_KEY` is a metered per-key credential. Shipping it via `--dart-define` puts it inside
/// the APK, where anyone who installs the app can extract it and spend our allowance from outside our
/// product. So the split is: this class READS the cache with the anon/publishable key (and is
/// therefore subject to RLS like every other client request), and the FUNCTION owns the provider key
/// and the only write path. Migration 0008 adds the `prices_cache` read policy this depends on.
///
/// ## Cache-first, never cache-only
///
/// A fresh cached read is served immediately, because a replay is a chart and a chart that takes five
/// seconds to appear is a chart nobody opens. When the row is stale or absent the function is asked
/// to refresh, and its answer is used DIRECTLY rather than re-read — so one tap costs one upstream
/// call instead of two round trips.
class SupabasePriceBarRepository implements PriceBarRepository {
  SupabasePriceBarRepository([SupabaseService? service])
      : _service = service ?? SupabaseService.instance;

  /// How old a cached row may be before it is refreshed.
  ///
  /// Generous relative to the bar, because a replay is historical by nature: a two-day-old H1 series
  /// replays identically to a two-minute-old one, and re-fetching it would burn metered allowance to
  /// change nothing. D1 rows therefore refresh rarely, which is correct.
  static const Duration maxCacheAge = Duration(hours: 6);

  final SupabaseService _service;

  SupabaseClient get _client => _service.client;

  @override
  bool get isStubbed => false;

  @override
  List<PriceSeriesRequest> get supportedSeries => supported;

  /// The catalogue the backend may fetch. A closed list, so neither side can be talked into spending
  /// a metered call on an arbitrary symbol.
  static const List<PriceSeriesRequest> supported = <PriceSeriesRequest>[
    PriceSeriesRequest(symbol: 'XAUUSD', timeframe: ReplayTimeframe.m15),
    PriceSeriesRequest(symbol: 'XAUUSD', timeframe: ReplayTimeframe.h1),
    PriceSeriesRequest(symbol: 'XAUUSD', timeframe: ReplayTimeframe.h4),
    PriceSeriesRequest(symbol: 'XAUUSD', timeframe: ReplayTimeframe.d1),
    PriceSeriesRequest(symbol: 'EURUSD', timeframe: ReplayTimeframe.h1),
    PriceSeriesRequest(symbol: 'EURUSD', timeframe: ReplayTimeframe.h4),
    PriceSeriesRequest(symbol: 'GBPUSD', timeframe: ReplayTimeframe.h1),
    PriceSeriesRequest(symbol: 'GBPUSD', timeframe: ReplayTimeframe.h4),
    PriceSeriesRequest(symbol: 'USDJPY', timeframe: ReplayTimeframe.h1),
    PriceSeriesRequest(symbol: 'US30', timeframe: ReplayTimeframe.h1),
  ];

  @override
  Future<PriceSeries> fetchSeries(PriceSeriesRequest request) async {
    final DateTime now = DateTime.now().toUtc();

    final PriceSeries? cached = await _readCache(request);
    if (cached != null) {
      final Duration? age = cached.ageAt(now);
      if (cached.isNotEmpty && age != null && age <= maxCacheAge) return cached;

      // Stale or empty: refresh. If the upstream call fails we return the STALE row rather than an
      // error — slightly old candles are far more use to a trader than an error card, and the series
      // still carries its own `asOf`, so the chart states how old it really is.
      final PriceSeries? refreshed = await _refresh(request);
      if (refreshed != null) return refreshed;
      return cached;
    }

    final PriceSeries? refreshed = await _refresh(request);
    if (refreshed == null) {
      throw const PriceBarException(PriceBarFailure.warming);
    }
    return refreshed;
  }

  /// The cached row, or null when there is none (or no session).
  ///
  /// No session means no honest way to be scoped by RLS, so this returns null and lets the caller
  /// decide. It does NOT throw: a cache miss is a normal condition, not an error.
  Future<PriceSeries?> _readCache(PriceSeriesRequest request) async {
    if (_client.auth.currentUser == null) return null;

    final List<Map<String, dynamic>> rows = await (_client
        .from('prices_cache')
        .select('symbol,timeframe,ohlc,updated_at')
        .eq('symbol', request.symbol.toUpperCase())
        .eq('timeframe', request.timeframe.wire)
        .limit(1))
        .timeout(SupabaseService.networkTimeout);

    if (rows.isEmpty) return null;
    final Map<String, dynamic> row = rows.first;

    return PriceSeries(
      request: request,
      bars: PriceBar.fromCacheList(row['ohlc']),
      asOf: DateTime.tryParse(row['updated_at'] as String? ?? ''),
      source: PriceSeriesSource.cache,
    );
  }

  /// Asks `market-bars` to refresh, and turns its answer into a series.
  ///
  /// A transport failure returns null so the caller can fall back to a stale cache; a classified
  /// function failure throws, because those are conditions the trader needs to hear about rather than
  /// have papered over. Conflating the two would make "the provider is down" indistinguishable from
  /// "this symbol has no history", which is false.
  Future<PriceSeries?> _refresh(PriceSeriesRequest request) async {
    final dynamic response;
    try {
      response = await _client.functions.invoke(
        'market-bars',
        // Only the symbol and the interval. No user id, no key — the function learns nothing about
        // the caller except that GoTrue already verified the token.
        body: <String, dynamic>{
          'symbol': request.symbol.toUpperCase(),
          'interval': request.timeframe.wire,
        },
      ).timeout(SupabaseService.networkTimeout);
    } on FunctionsHttpException catch (e) {
      // The STATUS is classified; the body never is. A function error can name tables and constraints.
      throw PriceBarException(_classify(e.status));
    } catch (_) {
      return null;
    }

    final Object? data = response.data;
    if (data is! Map<String, dynamic>) return null;

    final List<PriceBar> bars = PriceBar.fromCacheList(data['bars']);
    if (bars.isEmpty) return null;

    return PriceSeries(
      request: request,
      bars: bars,
      asOf: DateTime.tryParse(data['as_of'] as String? ?? ''),
      source: PriceSeriesSource.cache,
    );
  }

  /// Maps a function status onto the closed [PriceBarFailure] set.
  ///
  /// 404 is `unknownSeries` rather than a generic error, because "this symbol is not available" is
  /// something the trader can act on by choosing another one — reporting it identically to a transport
  /// failure would leave them retrying a request that cannot succeed.
  static PriceBarFailure _classify(int status) {
    if (status == 404) return PriceBarFailure.unknownSeries;
    if (status == 503) return PriceBarFailure.notConfigured;
    if (status == 401 || status == 403) return PriceBarFailure.unreachable;
    return PriceBarFailure.failed;
  }
}