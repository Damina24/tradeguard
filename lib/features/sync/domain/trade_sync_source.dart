/// Why a sync attempt failed.
///
/// A closed set rather than free text: the UI branches on these (offer retry on [rateLimited],
/// tell the trader their connection expired on [authFailed]) and the tests assert on a cause
/// rather than a message.
enum TradeSyncFailure {
  /// The provider could not be reached at all (DNS, timeout, 5xx).
  network,

  /// The provider rejected our token: expired, revoked, or never configured.
  authFailed,

  /// The provider asked us to slow down. [TradeSyncException.retryAfter] says for how long.
  rateLimited,

  /// The response arrived but could not be understood.
  malformedResponse,

  /// The account has no usable provider link (no external id configured).
  notConfigured,

  /// The provider answered correctly but returned nothing for this window.
  empty,

  /// Our own storage refused the write.
  persistenceFailed,

  /// The window we asked for is not something we will do (see `kMaxWindowDays`).
  windowTooLarge,
}

/// A sync failure whose [message] is safe to render.
///
/// Provider error bodies are never propagated: MetaAPI can echo account identifiers back, so
/// the raw text is kept in [detail] for logs only. Same pattern as `TradeImportException`.
class TradeSyncException implements Exception {
  const TradeSyncException(
    this.failure,
    this.message, {
    this.retryAfter,
    this.detail,
  });

  final TradeSyncFailure failure;

  /// Trader-safe copy.
  final String message;

  /// Seconds to wait before retrying, set for [TradeSyncFailure.rateLimited].
  final Duration? retryAfter;

  /// Raw provider text. Diagnostics and tests only — never rendered.
  final String? detail;

  /// True when re-running later is likely to succeed.
  bool get isRetryable => failure == TradeSyncFailure.network ||
      failure == TradeSyncFailure.rateLimited ||
      failure == TradeSyncFailure.persistenceFailed;

  @override
  String toString() => 'TradeSyncException(${failure.name}): $message';
}

/// One page of trades from a provider, still in the provider's own shape.
///
/// [deals] are raw maps on purpose: the provider's field names are a parser concern, and the
/// mapper is what turns them into canonical [TradeRecord]s.
class TradeSyncPage {
  const TradeSyncPage({
    required this.deals,
    this.nextCursor,
    this.hasMore = false,
  });

  const TradeSyncPage.empty()
      : deals = const <Map<String, dynamic>>[],
        nextCursor = null,
        hasMore = false;

  /// Raw provider records. Empty is a legitimate result, not an error.
  final List<Map<String, dynamic>> deals;

  /// Opaque provider cursor for the next page, when the provider pages by cursor.
  final String? nextCursor;

  /// Whether [nextCursor] may be followed.
  final bool hasMore;

  bool get isEmpty => deals.isEmpty;
}

/// The provider seam `sync-trades` talks through.
///
/// Deliberately narrow and credential-free: an implementation knows how to read trades from
/// one kind of broker and nothing else. It never sees a database, never normalizes, and never
/// decides what gets written. That is what keeps MetaAPI an implementation detail — swapping
/// it for another broker means adding a class here and changing one line of wiring.
///
/// Every implementation MUST:
/// * throw [TradeSyncException] (never a raw `HttpException`) so callers never see a stack;
/// * never log or return its credentials;
/// * respect [limit] so a sync cannot pull an unbounded window.
abstract class TradeSyncSource {
  /// Whether this source is a stub (no provider credentials configured).
  bool get isStubbed;

  /// Reads one page for [providerAccountId].
  ///
  /// [since] bounds the window; null means "everything the provider still has". [cursor]
  /// continues a previous page. [limit] is a hard cap the caller enforces and the provider
  /// should also honour.
  Future<TradeSyncPage> fetchTrades({
    required String providerAccountId,
    DateTime? since,
    String? cursor,
    int limit = 100,
  });
}