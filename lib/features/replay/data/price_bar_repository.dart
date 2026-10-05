import '../domain/price_series.dart';
import '../domain/price_series_request.dart';

/// Read access to OHLC bars — the `prices_cache` table, filled by the `market-bars` Edge Function
/// from TwelveData.
///
/// The seam exists for the same reason `PatternRepository` has one, and the same reason
/// `AiReviewRepository` does: **no caller may choose whose data to read.** There is deliberately no
/// `userId` parameter on any method. Price history is not private data, but the *cache freshness* is
/// shared, so identity still comes from the session inside the implementation rather than from a
/// widget, and a caller cannot ask for a series as somebody else.
///
/// ## Why the client never calls TwelveData directly
///
/// `TWELVEDATA_KEY` is a metered, per-key credential. Shipping it in a `--dart-define` puts it in the
/// APK, where it can be extracted by anyone who installs the app — and then spent at our expense,
/// rate-limited against our account, from outside our product. So the fetch is server-side only:
/// the client reads the cached rows and asks the function to refresh them. See
/// `supabase/functions/market-bars/`.
abstract class PriceBarRepository {
  /// True when bars are generated locally rather than fetched, so the chart can say so.
  bool get isStubbed;

  /// The symbol/timeframe pairs this build can replay.
  ///
  /// A fixed list rather than a free-text field, for the same reason the timeframe is an enum: the
  /// set of series that can be cached has to be knowable without spending a metered call.
  List<PriceSeriesRequest> get supportedSeries;

  /// The bars for [request].
  ///
  /// Throws [PriceBarException] on failure. Returning an empty list instead would render as "there is
  /// no history for this symbol", which is a different and misleading claim from "the fetch failed".
  Future<PriceSeries> fetchSeries(PriceSeriesRequest request);
}

/// Why bars could not be read.
///
/// A closed set, never a raw message: a PostgREST or Edge Function error can name tables, columns and
/// constraints. The screen needs to say something different for "the backend is not deployed yet" than
/// for "you are offline", and neither should read as "this symbol has no history".
enum PriceBarFailure {
  /// No `TWELVEDATA_KEY` or no Supabase credentials on the backend. The trader cannot fix it; the
  /// product is not deployed.
  notConfigured('Price history is not available on this build yet.'),

  /// The cache and the function could not be reached.
  unreachable('Could not load price history. Try again shortly.'),

  /// The fetch ran but failed. Deliberately vague.
  failed('Could not load price history for this symbol.'),

  /// TwelveData does not serve this symbol. Reported identically to a missing cache row so the
  /// endpoint cannot be used to probe for what data a deployment holds.
  unknownSeries('That symbol or timeframe is not available.'),

  /// The cache is being written and has nothing usable yet.
  warming('Price history for this symbol is still being fetched.');

  const PriceBarFailure(this.message);

  /// Trader-safe wording. Never contains a table name, a constraint or a provider error body.
  final String message;
}

/// A failed bar read. Carries a [failure] the UI can branch on, never a raw message.
class PriceBarException implements Exception {
  const PriceBarException(this.failure);

  final PriceBarFailure failure;

  String get message => failure.message;

  @override
  String toString() => 'PriceBarException: ${failure.name}';
}