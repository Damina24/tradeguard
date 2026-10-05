import '../domain/price_bar.dart';
import '../domain/price_series.dart';
import '../domain/price_series_request.dart';
import 'price_bar_repository.dart';

/// Synthetic OHLC bars, so the whole replay feature is exercisable with no `TWELVEDATA_KEY`
/// and no Supabase project.
///
/// Four properties, each deliberate:
///
///   * **Deterministic.** Seeded by the symbol, so XAUUSD H1 is the same series on every launch, on
///     every device and in every test. A mock that reshuffled per run would make widget tests flaky
///     and screenshots unreproducible — and it would misrepresent the real feature, where the same
///     cached bars always replay the same way.
///   * **Generated, not recalled.** The bars come from a seeded walk, NOT from the trader's
///     `MockData.trades()`. Inventing bars to agree with a set of trades would be a second, hidden
///     claim that those trades happened at those prices. Nothing here derives from the journal.
///   * **Labelled.** [isStubbed] is true and the chart says `SYNTHETIC DEMO`. A generated chart shown
///     unlabelled is indistinguishable from a market chart, which for a backtest is the single most
///     misleading thing this product could ship.
///   * **Structurally real.** The walk produces trend and range phases, stop-outs and target hits, so
///     the engine's rules — including its pessimistic same-bar rule — are genuinely reached instead of
///     every setup resolving the same way.
class MockPriceBarRepository implements PriceBarRepository {
  MockPriceBarRepository({this.barCount = 240, this.latency = Duration.zero});

  /// Bars generated per series. 240 H1 bars is ten days: enough for a scan to clear its reporting
  /// floor, few enough to stay responsive on a phone.
  final int barCount;

  /// Artificial delay, so a test can hold the loading state open.
  final Duration latency;

  final Map<String, List<PriceBar>> _cache = <String, List<PriceBar>>{};

  /// Symbol/timeframe pairs this mock refuses to serve, so the "not available" path is testable.
  final Set<String> unavailable = <String>{};

  /// When true, every read throws [PriceBarFailure.unreachable].
  bool failing = false;

  @override
  bool get isStubbed => true;

  @override
  List<PriceSeriesRequest> get supportedSeries => defaultSeries;

  /// The symbols a prop trader actually watches, matching the journal seed and `docs/RISK_DISCLAIMER.md`.
  static const List<PriceSeriesRequest> defaultSeries = <PriceSeriesRequest>[
    PriceSeriesRequest(symbol: 'XAUUSD', timeframe: ReplayTimeframe.h1),
    PriceSeriesRequest(symbol: 'EURUSD', timeframe: ReplayTimeframe.h1),
    PriceSeriesRequest(symbol: 'GBPUSD', timeframe: ReplayTimeframe.h4),
    PriceSeriesRequest(symbol: 'US30', timeframe: ReplayTimeframe.h1),
  ];

  /// Anchor price and typical bar range per symbol.
  ///
  /// The ranges are chosen so a stop of one bar-range is a plausible gold/FX stop. If the demo
  /// generated bars of wildly different proportions to the levels a trader would pick, the feature
  /// would only ever be exercised in states real setups never reach.
  static const Map<String, ({double base, double tick, int decimals})> profile =
      <String, ({double base, double tick, int decimals})>{
    'XAUUSD': (base: 2345.50, tick: 4.20, decimals: 2),
    'EURUSD': (base: 1.08720, tick: 0.00180, decimals: 5),
    'GBPUSD': (base: 1.27100, tick: 0.00240, decimals: 5),
    'US30': (base: 39120.0, tick: 68.0, decimals: 2),
  };

  @override
  Future<PriceSeries> fetchSeries(PriceSeriesRequest request) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (failing) throw const PriceBarException(PriceBarFailure.unreachable);
    if (unavailable.contains(request.symbol.toUpperCase())) {
      throw const PriceBarException(PriceBarFailure.unknownSeries);
    }

    final List<PriceBar> bars =
        _cache.putIfAbsent(request.cacheKey, () => _generate(request));

    return PriceSeries(
      request: request,
      bars: List<PriceBar>.unmodifiable(bars),
      // Stamped as now AND reported as [PriceSeriesSource.demo]: the chart shows an age and the
      // synthetic label together, so nothing here can be read as a fresh market quote.
      asOf: DateTime.now().toUtc(),
      source: PriceSeriesSource.demo,
      isStubbed: true,
    );
  }

  /// The generator: a seeded walk with a slow drift and per-bar shocks.
  ///
  /// A seeded LCG rather than `dart:math`'s `Random`, because the library's algorithm is an
  /// implementation detail that has changed between Dart releases — and a demo chart that moved when
  /// the SDK did would break the tests that assert on it.
  List<PriceBar> _generate(PriceSeriesRequest request) {
    final String symbol = request.symbol.toUpperCase();
    final ({double base, double tick, int decimals}) shape =
        profile[symbol] ?? (base: 100.0, tick: 1.0, decimals: 2);

    final _Lcg rng = _Lcg(_seed(symbol, request.timeframe));
    double price = shape.base;
    double drift = 0;
    final DateTime end = DateTime.now().toUtc();
    final DateTime start =
        end.subtract(request.timeframe.barDuration * (barCount - 1));

    final List<PriceBar> bars = <PriceBar>[];
    for (int i = 0; i < barCount; i++) {
      final double roll = rng.next();
      // The drift is what produces trends and pullbacks rather than pure noise. A pure random walk
      // almost never revisits a level, so every setup would fill at bar zero and nothing after it
      // would be reachable — the replay would look broken while being technically correct.
      drift = drift * 0.85 + (roll - 0.5) * shape.tick * 0.9;
      final double open = price;
      final double close = open + drift + (roll - 0.5) * shape.tick;

      // Wicks sit outside the body, so every generated bar is well-formed and `PriceBar.isWellFormed`
      // has something real to police.
      final double upperWick = rng.next() * shape.tick * 0.6;
      final double lowerWick = rng.next() * shape.tick * 0.6;
      final double high = (open > close ? open : close) + upperWick;
      final double low = (open < close ? open : close) - lowerWick;

      bars.add(
        PriceBar(
          time: start.add(request.timeframe.barDuration * i),
          open: _round(open, shape.decimals),
          high: _round(high, shape.decimals),
          low: _round(low, shape.decimals),
          close: _round(close, shape.decimals),
        ),
      );
      price = close;
    }

    return List<PriceBar>.unmodifiable(bars);
  }

  /// Per-series seed, so each symbol/timeframe gets its own walk while staying reproducible.
  static int _seed(String symbol, ReplayTimeframe timeframe) {
    int h = 7;
    for (final int unit in symbol.codeUnits) {
      h = (h * 31 + unit) % _modulus;
    }
    h = (h * 31 + timeframe.index) % _modulus;
    return h == 0 ? 1 : h;
  }

  /// Rounded to the symbol's own precision, so the chart axis reads like the market's rather than
  /// showing eight meaningless decimals on EURUSD.
  static double _round(double v, int decimals) =>
      double.parse(v.toStringAsFixed(decimals));

  static const int _modulus = 0x7fffffff;
}

/// A tiny deterministic pseudo-random source, private to this file.
///
/// Numerical Recipes LCG constants: a small multiplier and increment with a full period modulo 2^31.
/// Deliberately hand-rolled rather than `Random(seed)` — the library's algorithm is an implementation
/// detail that has changed between Dart releases, and a demo chart that moved when the SDK did would
/// break the tests asserting on it. Not cryptographic, and it must never be used for anything except
/// drawing a fake price series.
class _Lcg {
  _Lcg(this.state);

  int state;

  /// Advances the generator and returns a double in 0..1.
  double next() {
    state = (state * 1103515245 + 12345) % 0x7fffffff;
    return state / 0x7fffffff;
  }
}