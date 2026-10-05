/// One OHLC bar, and the only price primitive the replay works with.
///
/// Deliberately a plain data holder with no replay logic in it, mirroring `Trade` and `AiReview`:
/// the bar says what the market did, and [ReplayEngine] says what a setup would have done about it.
/// Keeping those apart is what lets the same bar list be replayed against several setups without
/// any of them re-deriving prices.
///
/// Parsing accepts **both** shapes that can reach the app:
///
///   * `prices_cache.ohlc` (`jsonb`), written by the `market-bars` Edge Function from TwelveData;
///   * TwelveData's own `values` rows, in case a future producer forwards them unnormalised.
///
/// Anything that is not a finite, self-consistent bar is dropped by [fromCacheList] rather than
/// thrown on. A single malformed row must not cost the trader the rest of the series — but a bar
/// whose high is below its low *is* refused, because rendering it would draw a chart the market
/// cannot have produced, and every backtest claim on screen rests on that chart.
class PriceBar {
  const PriceBar({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  /// Bar open time. Always the **start** of the bar's period, matching TwelveData.
  final DateTime time;

  final double open;
  final double high;
  final double low;
  final double close;

  /// Whether the bar is internally consistent and safe to render or replay.
  ///
  /// `high >= max(open, close)` and `low <= min(open, close)`. Deliberately NOT strict about
  /// `high >= low` beyond this: a provider that is off by a rounding step still yields a usable
  /// bar, whereas refusing it would leave the trader with no replay at all.
  bool get isWellFormed =>
      open.isFinite &&
      high.isFinite &&
      low.isFinite &&
      close.isFinite &&
      high >= (open > close ? open : close) &&
      low <= (open < close ? open : close);

  /// Whether price traded at [price] at any point in this bar.
  ///
  /// Inclusive at both ends: a stop exactly at the bar's low is hit, which is the pessimistic read
  /// the engine needs.
  bool contains(double price) => price >= low && price <= high;

  /// Midpoint of the range. Used to derive a plausible entry for a bar that has already closed.
  double get mid => (high + low) / 2;

  /// Full range, in price. The stop of a "this bar" setup is derived from this.
  double get range => high - low;

  /// The `jsonb` shape stored in `prices_cache.ohlc`.
  ///
  /// Short keys, because the whole series lives in one row: a 500-bar H1 series is hundreds of
  /// kilobytes of JSON and long key names are pure overhead.
  Map<String, dynamic> toCacheJson() => <String, dynamic>{
        't': time.toUtc().toIso8601String(),
        'o': open,
        'h': high,
        'l': low,
        'c': close,
      };

  /// Parses one cached bar. Returns null when the shape or the numbers are unusable.
  ///
  /// Null rather than a throw, because the caller is parsing a list it does not control and one bad
  /// entry must not discard the series.
  static PriceBar? tryParse(Object? raw) {
    if (raw is Map) {
      final Map<Object?, Object?> row = raw;
      return _build(
        row['t'] ?? row['datetime'] ?? row['time'],
        row['o'] ?? row['open'],
        row['h'] ?? row['high'],
        row['l'] ?? row['low'],
        row['c'] ?? row['close'],
      );
    }
    // TwelveData can also answer with positional tuples: [datetime, open, high, low, close].
    if (raw is List && raw.length >= 5) {
      return _build(raw[0], raw[1], raw[2], raw[3], raw[4]);
    }
    return null;
  }

  static PriceBar? _build(Object? t, Object? o, Object? h, Object? l, Object? c) {
    final DateTime? time = _time(t);
    if (time == null) return null;
    final double? open = _num(o);
    final double? high = _num(h);
    final double? low = _num(l);
    final double? close = _num(c);
    if (open == null || high == null || low == null || close == null) return null;
    final PriceBar bar =
        PriceBar(time: time, open: open, high: high, low: low, close: close);
    return bar.isWellFormed ? bar : null;
  }

  /// Parses a series, dropping unusable entries, then sorting oldest → newest.
  ///
  /// Sorting is not cosmetic. Providers hand back newest-first, and the engine walks forward in
  /// time; replaying a series backwards would fill at a price that had not happened yet and quietly
  /// produce a backtest that could not have been traded. Duplicate timestamps collapse to the LAST
  /// occurrence, so a provider restating a bar is corrected rather than doubled.
  static List<PriceBar> fromCacheList(Object? raw) {
    if (raw is! List) return const <PriceBar>[];
    final Map<DateTime, PriceBar> byTime = <DateTime, PriceBar>{};
    for (final Object? entry in raw) {
      final PriceBar? bar = tryParse(entry);
      if (bar != null) byTime[bar.time] = bar;
    }
    final List<PriceBar> bars = byTime.values.toList()
      ..sort((PriceBar a, PriceBar b) => a.time.compareTo(b.time));
    return List<PriceBar>.unmodifiable(bars);
  }

  static DateTime? _time(Object? v) {
    if (v is DateTime) return v.toUtc();
    if (v is! String || v.trim().isEmpty) return null;
    return DateTime.tryParse(v)?.toUtc();
  }

  /// Finite number or null. Never NaN, never Infinity — either would poison every R downstream.
  static double? _num(Object? v) {
    if (v is num) return v.isFinite ? v.toDouble() : null;
    if (v is String) {
      final double? parsed = double.tryParse(v.trim());
      return (parsed != null && parsed.isFinite) ? parsed : null;
    }
    return null;
  }

  @override
  String toString() =>
      'PriceBar(${time.toIso8601String()} o:$open h:$high l:$low c:$close)';
}