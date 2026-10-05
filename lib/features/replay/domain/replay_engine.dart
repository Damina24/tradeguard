import 'price_bar.dart';
import 'replay_result.dart';
import 'replay_setup.dart';

/// Replays one setup across a bar series, bar by bar.
///
/// Pure, synchronous, total and deterministic: same bars in, same result out, every run. That is a
/// hard requirement rather than a nicety — a backtest that answers differently each time it is
/// opened is worse than no backtest, because the trader cannot check it.
///
/// ## The rules that decide the numbers
///
/// Four fill/exit conventions, each chosen to be **pessimistic**. Every one of them costs the
/// backtest performance, which is the direction that matters when the alternative is a flattering
/// number on a screen a trader might act on.
///
///  1. **A fill needs a bar that trades through the entry, and fills at the worse of entry/open.**
///     If a bar gapped past the level, its open is the only price that existed, so that is the fill.
///  2. **The entry bar cannot also be the exit bar.** A trader cannot enter and be stopped out
///     inside one OHLC bar unless that bar's range spans both levels — and if it does, rule 3
///     applies anyway. Allowing it would manufacture outcomes from bar width alone.
///  3. **When one bar spans BOTH the stop and the target, it is a loss.** OHLC does not record
///     intrabar order, so the sequence is unknowable, and "unknowable" must resolve to the worse
///     outcome. This is the single most consequential rule here: resolving it optimistically is the
///     classic way a losing system gets reported as a winning one.
///  4. **No exit is invented at the end of the series.** A setup still open when the bars run out is
///     [ReplayStatus.unresolved] — marked to market and labelled, never quietly closed at a
///     convenient price to tidy the chart.
class ReplayEngine {
  const ReplayEngine();

  /// Replays [setup] over [bars].
  ///
  /// Total: every input yields a [ReplayResult], including an invalid setup, an empty series and a
  /// setup that never triggers, so a caller never has to guard.
  ReplayResult run(List<PriceBar> bars, ReplaySetup setup) {
    if (!setup.isValid) return ReplayResult.invalid(setup);
    if (bars.isEmpty) return ReplayResult.notFilled(setup);

    final int? fillIndex = _findFill(bars, setup);
    if (fillIndex == null) return ReplayResult.notFilled(setup);

    final double fillPrice = _fillPrice(bars[fillIndex], setup);

    // Rule 2 — the exit scan starts on the bar AFTER the fill.
    double best = fillPrice;
    double worst = fillPrice;

    for (int i = fillIndex + 1; i < bars.length; i++) {
      final PriceBar bar = bars[i];

      // Rule 3 — the stop is checked first, so a bar spanning both levels resolves as a loss.
      final bool stopTouched = setup.isLong
          ? bar.low <= setup.stop
          : bar.high >= setup.stop;
      if (stopTouched) {
        return ReplayResult(
          setup: setup,
          status: ReplayStatus.stopHit,
          fillIndex: fillIndex,
          fillPrice: fillPrice,
          exitIndex: i,
          exitPrice: _exitPrice(bar, setup.stop, true, setup.isLong),
          barsHeld: i - fillIndex,
          mfeR: setup.rBetween(fillPrice, best),
          maeR: setup.rBetween(fillPrice, worst),
        );
      }

      final double? target = setup.target;
      if (target != null) {
        final bool targetTouched = setup.isLong
            ? bar.high >= target
            : bar.low <= target;
        if (targetTouched) {
          return ReplayResult(
            setup: setup,
            status: ReplayStatus.targetHit,
            fillIndex: fillIndex,
            fillPrice: fillPrice,
            exitIndex: i,
            exitPrice: _exitPrice(bar, target, false, setup.isLong),
            barsHeld: i - fillIndex,
            mfeR: setup.rBetween(fillPrice, best),
            maeR: setup.rBetween(fillPrice, worst),
          );
        }
      }

      // Excursions are measured on CLOSES only. Using the bar high/low here would report an MFE the
      // position was never closed at, and would let the MAE of a stop-out bar read as though the
      // trader had chosen to hold through it.
      if (setup.isLong) {
        if (bar.close > best) best = bar.close;
        if (bar.close < worst) worst = bar.close;
      } else {
        if (bar.close < best) best = bar.close;
        if (bar.close > worst) worst = bar.close;
      }
    }

    // Rule 4 — still open at the end of the data: marked to market, not invented.
    final double last = bars.last.close;
    // The final close is part of the open trade, so it joins the excursion extremes before they are
    // priced. A position left open on the last bar has certainly reached that bar's close.
    final double bestSeen =
        setup.isLong ? (last > best ? last : best) : (last < best ? best : last);
    final double worstSeen = setup.isLong
        ? (last < worst ? last : worst)
        : (last > worst ? worst : last);

    return ReplayResult(
      setup: setup,
      status: ReplayStatus.unresolved,
      fillIndex: fillIndex,
      fillPrice: fillPrice,
      exitPrice: last,
      barsHeld: bars.length - 1 - fillIndex,
      mfeR: setup.rBetween(fillPrice, bestSeen),
      maeR: setup.rBetween(fillPrice, worstSeen),
    );
  }

  /// First bar whose range contains the entry price, or null when price never gets there.
  ///
  /// Scanning from the start answers "what happened at the FIRST opportunity", which is the question
  /// a trader replaying a level is actually asking.
  static int? _findFill(List<PriceBar> bars, ReplaySetup setup) {
    for (int i = 0; i < bars.length; i++) {
      if (bars[i].contains(setup.entry)) return i;
    }
    return null;
  }

  /// Rule 1 — fill at the entry, or at the open when the series gapped past it.
  static double _fillPrice(PriceBar bar, ReplaySetup setup) {
    final bool gappedThrough =
        setup.isLong ? bar.open > setup.entry : bar.open < setup.entry;
    return gappedThrough ? bar.open : setup.entry;
  }

  /// Exit price, taking the open when the bar GAPPED straight past the level.
///
/// Otherwise the exit IS the level, because price had to travel there. A gap means the bar opened
/// already beyond the level, and then the open is the only price that existed:
///
///   * a **long target** (110) is cleared from below — a gap means `open > 110`, and the fill is the
///     open, which is BETTER than planned;
///   * a **long stop** (95) is broken from above — a gap means `open < 95`, and the fill is the open,
///     which is WORSE than planned;
///   * a **short target** (90) is cleared from above — a gap means `open < 90`;
///   * a **short stop** (105) is broken from below — a gap means `open > 105`.
///
/// So a stop gap can only hurt and a target gap can only help. Getting this backwards would turn every
/// gapped winner into a loser, which is why it is spelled out here rather than inferred at the call
/// sites.
static double _exitPrice(PriceBar bar, double level, bool isStop, bool isLong) {
    final bool gapped = isLong
        // Long: the target is reached upward, the stop is broken downward.
        ? (isStop ? bar.open < level : bar.open > level)
        // Short: mirrored.
        : (isStop ? bar.open > level : bar.open < level);
    return gapped ? bar.open : level;
  }
}