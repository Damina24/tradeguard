/// A symbol + timeframe pair, as the cache is keyed.
///
/// Value type with correct `==`/`hashCode`, because it is used as a Riverpod family key — two
/// lookups of "XAUUSD H1" must resolve to the same provider or the screen would refetch on every
/// rebuild.
class PriceSeriesRequest {
  const PriceSeriesRequest({required this.symbol, required this.timeframe});

  final String symbol;
  final ReplayTimeframe timeframe;

  /// The `prices_cache` primary key, verbatim.
  String get cacheKey => '${symbol.toUpperCase()}|${timeframe.wire}';

  @override
  bool operator ==(Object other) =>
      other is PriceSeriesRequest &&
      other.symbol.toUpperCase() == symbol.toUpperCase() &&
      other.timeframe == timeframe;

  @override
  int get hashCode => Object.hash(symbol.toUpperCase(), timeframe);

  @override
  String toString() => '$symbol ${timeframe.wire}';
}

/// Bar intervals the replay can request.
///
/// A closed set rather than a free-text timeframe. Every value is one TwelveData actually serves,
/// and — more importantly — a free-text field here would be a field the Edge Function has to
/// sanitise before spending a metered API call on it.
enum ReplayTimeframe {
  m15('15min', 'M15', Duration(minutes: 15)),
  h1('1h', 'H1', Duration(hours: 1)),
  h4('4h', 'H4', Duration(hours: 4)),
  d1('1day', 'D1', Duration(days: 1));

  const ReplayTimeframe(this.wire, this.label, this.barDuration);

  /// The exact string TwelveData and `prices_cache` use.
  final String wire;

  /// What the chip reads on screen.
  final String label;

  /// How much wall-clock one bar spans. Drives the freshness calculation.
  final Duration barDuration;

  static ReplayTimeframe fromWire(String? wire) {
    for (final ReplayTimeframe t in ReplayTimeframe.values) {
      if (t.wire == wire) return t;
    }
    return ReplayTimeframe.h1;
  }
}