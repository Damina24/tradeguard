import 'price_bar.dart';
import 'price_series_request.dart';

/// A bar series plus everything the UI must say about it.
///
/// Wrapping the bars rather than passing a bare `List<PriceBar>` is deliberate: a chart of price
/// with no idea where the data came from is how a demo series gets mistaken for the market. Carrying
/// [source] and [asOf] on the result means the screen physically cannot render a cached series
/// without also being able to say "cached 4m ago".
class PriceSeries {
  const PriceSeries({
    required this.request,
    required this.bars,
    this.asOf,
    this.source = PriceSeriesSource.cache,
    this.isStubbed = false,
  });

  /// An empty series, used by the loading and error states.
  static PriceSeries empty(PriceSeriesRequest request) => PriceSeries(
        request: request,
        bars: const <PriceBar>[],
      );

  final PriceSeriesRequest request;

  /// Oldest → newest. Sorted by [PriceBar.fromCacheList], so a provider returning newest-first is
  /// corrected rather than replayed backwards.
  final List<PriceBar> bars;

  /// When the cached row was written. Null when the source did not report one.
  final DateTime? asOf;

  /// Where these bars came from. Drives the provenance line on the chart.
  final PriceSeriesSource source;

  /// Whether these bars were generated locally rather than fetched.
  ///
  /// Carried on the DATA rather than read from a second provider, so the chart and the badge
  /// describing it can never come from two places that disagree — the same argument as
  /// `AiReviewState.isStubbed`.
  final bool isStubbed;

  bool get isEmpty => bars.isEmpty;

  bool get isNotEmpty => bars.isNotEmpty;

  /// The last bar's close — the series' most recent price.
  double? get lastClose => bars.isEmpty ? null : bars.last.close;

  /// How many bars the series holds. Stated on screen: a "backtest" over four bars is a chart, not
  /// evidence, and the count is the first thing a trader should be able to check.
  int get barCount => bars.length;

  /// Total wall-clock span the bars cover.
  Duration get span => bars.length < 2
      ? Duration.zero
      : bars.last.time.difference(bars.first.time);

  /// Bars per day the series averages, for the "how much history is this" line.
  double get barsPerDay {
    if (bars.length < 2) return 0;
    final double days = span.inHours / 24;
    if (days <= 0) return 0;
    return double.parse((bars.length / days).toStringAsFixed(1));
  }

  /// How old the data is relative to [now].
  ///
  /// Null when [asOf] is unknown. A series with no timestamp is not silently treated as fresh — the
  /// screen shows the provenance line without an age rather than claiming "live".
  Duration? ageAt(DateTime now) {
    final DateTime? stamp = asOf;
    if (stamp == null) return null;
    final Duration age = now.difference(stamp);
    return age.isNegative ? Duration.zero : age;
  }

  /// The bar range's extremes, used to scale the chart without inspecting the list in the widget.
  ///
  /// Returns null when the series is empty, so the chart can show its own empty state rather than
  /// dividing by zero on a `minY`/`maxY`.
  ({double low, double high})? get extremes {
    if (bars.isEmpty) return null;
    double low = bars.first.low;
    double high = bars.first.high;
    for (final PriceBar b in bars) {
      if (b.low < low) low = b.low;
      if (b.high > high) high = b.high;
    }
    return (low: low, high: high);
  }
}

/// Where a series came from.
///
/// A closed set with a label each, because "the data is real but old" and "this is a generated demo"
/// are very different things to print next to a chart, and neither may be silently omitted.
enum PriceSeriesSource {
  /// Read from `prices_cache`, written by the `market-bars` Edge Function from TwelveData.
  cache('Cached market data', false),

  /// Generated locally by `MockPriceBarRepository`. Not the market.
  demo('Synthetic demo data', true);

  const PriceSeriesSource(this.label, this.isDemo);

  /// Provenance wording for the chart footer.
  final String label;

  /// True when the bars are not real market prices.
  final bool isDemo;
}