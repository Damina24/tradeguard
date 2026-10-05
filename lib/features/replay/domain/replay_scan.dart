import 'price_bar.dart';
import 'replay_engine.dart';
import 'replay_result.dart';
import 'replay_setup.dart';

/// The same setup applied from every bar in the series — "how often would this have worked?"
///
/// This is where a backtest most easily lies, so the aggregate carries its own sample size and its
/// own floor:
///
///   * **Only trades count.** A setup that never triggered is excluded from the denominator
///     ([ReplayResult.countsAsTrade]). Counting them as losses would make a selective entry look like
///     it missed money.
///   * **Unresolved trades are trades, but not wins.** They are in the denominator, because the
///     position existed and held risk; they are not in the numerator. Anything else quietly promotes
///     "still open" into "profitable".
///   * **[isInsufficientData] is a first-class result, not an error.** Below [minimumTrades] there is
///     no evidence, and the screen must say so instead of printing a confident win rate off three
///     bars. Same rule, same reason as `LeakDetector` in task 2.4.
class ReplayScan {
  const ReplayScan({
    required this.results,
    required this.minimumTrades,
  });

  /// Every attempt, in bar order. Includes the ones that never filled.
  final List<ReplayResult> results;

  /// The reporting floor. Below this many trades, [isInsufficientData] is true.
  final int minimumTrades;

  /// The empty scan, used by the loading and error states.
  factory ReplayScan.empty({int minimumTrades = 10}) => ReplayScan(
        results: const <ReplayResult>[],
        minimumTrades: minimumTrades,
      );

  /// Runs [setup] from every bar in [bars].
  ///
  /// Uses the SAME [ReplayEngine] and the SAME conventions as a single replay, so a scan and a
  /// one-shot replay can never disagree about the same bar. Two implementations of the fill rules
  /// would eventually disagree, and the screen would show a rate its own detail card contradicts.
  static ReplayScan run({
    required List<PriceBar> bars,
    required ReplaySetup setup,
    ReplayEngine engine = const ReplayEngine(),
    ReplayScanThresholds thresholds = const ReplayScanThresholds(),
  }) {
    if (bars.isEmpty || !setup.isValid) {
      return ReplayScan(
        results: const <ReplayResult>[],
        minimumTrades: thresholds.minTrades,
      );
    }

    final List<ReplayResult> results = <ReplayResult>[];
    for (int i = 0; i < bars.length; i++) {
      results.add(engine.run(bars.sublist(i), reanchor(setup, bars[i])));
    }

    return ReplayScan(
      results: List<ReplayResult>.unmodifiable(results),
      minimumTrades: thresholds.minTrades,
    );
  }

  /// Re-anchors [setup] so its entry is the close of [bar], keeping the stop DISTANCE and the R
  /// multiple the trader chose.
  ///
  /// Holding the levels relative rather than absolute is the whole difference between "what would
  /// this setup have done at each bar" and the same price level evaluated once. Without it, a scan
  /// would just replay bar zero repeatedly.
  static ReplaySetup reanchor(ReplaySetup setup, PriceBar bar) {
    final double entry = bar.close;
    final double stopDistance = setup.riskDistance;
    final bool long = setup.isLong;
    final double? targetR = setup.rewardRisk;
    return ReplaySetup(
      symbol: setup.symbol,
      direction: setup.direction,
      entry: entry,
      stop: long ? entry - stopDistance : entry + stopDistance,
      target: targetR == null
          ? null
          : (long
              ? entry + (stopDistance * targetR)
              : entry - (stopDistance * targetR)),
      lots: setup.lots,
      balance: setup.balance,
    );
  }

  /// Results that actually traded, in bar order.
  List<ReplayResult> get trades => results
      .where((ReplayResult r) => r.countsAsTrade)
      .toList(growable: false);

  /// Attempts where the entry was never reached.
  List<ReplayResult> get unfilled => results
      .where((ReplayResult r) => r.status == ReplayStatus.notFilled)
      .toList(growable: false);

  /// Trades that reached the target.
  int get wins => trades.where((ReplayResult r) => r.isWin).length;

  /// Trades that hit the stop.
  int get losses => trades.where((ReplayResult r) => r.isLoss).length;

  /// Trades still open at the end of the series.
  int get unresolved => trades
      .where((ReplayResult r) => r.status == ReplayStatus.unresolved)
      .length;

  /// How many setups were attempted in total.
  int get attempts => results.length;

  /// Trades in the denominator — the honest sample size for every claim in this class.
  int get sampleTrades => trades.length;

  /// Fewer trades than [minimumTrades], so no rate below should be believed or shown as fact.
  bool get isInsufficientData => sampleTrades < minimumTrades;

  /// Win rate as a percentage of [sampleTrades], or null when nothing traded.
  ///
  /// Null rather than zero on an empty sample: "0% win rate" is a damning verdict about a system that
  /// never ran, and "—" is the honest reading.
  double? get winRatePct {
    if (sampleTrades == 0) return null;
    return double.parse(((wins / sampleTrades) * 100).toStringAsFixed(1));
  }

  /// Sum of every trade's R, or null when nothing traded.
  ///
  /// In R rather than money on purpose: R is the only unit in which setups with different stops and
  /// different lot sizes can be added without one trade dominating the total.
  double? get totalR {
    if (sampleTrades == 0) return null;
    double sum = 0;
    for (final ReplayResult r in trades) {
      sum += r.rMultiple ?? 0;
    }
    return double.parse(sum.toStringAsFixed(2));
  }

  /// Average R per trade, or null when nothing traded.
  double? get expectancyR {
    final double? total = totalR;
    if (total == null || sampleTrades == 0) return null;
    return double.parse((total / sampleTrades).toStringAsFixed(2));
  }

  /// Gross profit in R ÷ gross loss in R, or null when there were no losers.
  ///
  /// Null rather than infinity on a flawless run: a profit factor with no losses to divide by is not
  /// a number, and printing "∞" beside a backtest invites the reader to treat it as a measured edge.
  double? get profitFactorR {
    double gained = 0;
    double lost = 0;
    for (final ReplayResult r in trades) {
      final double? value = r.rMultiple;
      if (value == null) continue;
      if (value > 0) {
        gained += value;
      } else if (value < 0) {
        lost += value.abs();
      }
    }
    if (lost == 0) return null;
    return double.parse((gained / lost).toStringAsFixed(2));
  }

  /// Worst adverse excursion across all trades, in R. Null when nothing traded.
  ///
  /// The risk number a prop trader actually needs: if the worst excursion here is -1.4R then the stop
  /// was not the real risk, and no average-R figure in this class hides that.
  double? get worstMaeR {
    double? worst;
    for (final ReplayResult r in trades) {
      final double? mae = r.maeR;
      if (mae == null) continue;
      if (worst == null || mae < worst) worst = mae;
    }
    return worst;
  }

  /// Best excursion across all trades, in R. Null when nothing traded.
  double? get bestMfeR {
    double? best;
    for (final ReplayResult r in trades) {
      final double? mfe = r.mfeR;
      if (mfe == null) continue;
      if (best == null || mfe > best) best = mfe;
    }
    return best;
  }
}

/// Reporting floor for a scan.
///
/// Injectable so a test can drive the exact boundary — the same shape `LeakThresholds` uses in
/// task 2.4.
class ReplayScanThresholds {
  const ReplayScanThresholds({this.minTrades = 10});

  /// Trades required before a rate is stated as a finding.
  ///
  /// Ten, not five: a scan re-anchors on every bar, so neighbouring results are strongly correlated
  /// — one trend produces a dozen apparent "trades" at once. Five correlated wins is not evidence of
  /// an edge, and the distinction matters here precisely because the sample LOOKS large.
  final int minTrades;
}