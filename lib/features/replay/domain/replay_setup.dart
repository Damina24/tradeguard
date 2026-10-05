import '../../../core/models/trade.dart';
import '../../../core/utils/trading_math.dart';

/// What the trader is asking the replay to test: "had I taken this trade here, what happened?"
///
/// Not a strategy. Replay lite deliberately takes the *levels* the trader already recorded (entry,
/// stop, target) and finds the first bar where that setup would have filled. There is no
/// indicator, no signal feed and no auto-parameter search, for three reasons that are all about
/// honesty rather than effort:
///
///   * A backtest that picks its own entries from the same bars it is scored on can only look good.
///   * The product's journal already stores `entry`/`sl`/`tp` per trade, so replay reuses fields
///     that exist rather than inventing a parallel vocabulary.
///   * `docs/RISK_DISCLAIMER.md` calls backtests *hypothetical*. A setup the trader chose themselves
///     is a far more honest hypothetical than one a model invented for them.
///
/// Every derived number comes from [TradingMath], so a pip and an R mean exactly what they mean
/// everywhere else in the app.
class ReplaySetup {
  const ReplaySetup({
    required this.symbol,
    required this.direction,
    required this.entry,
    required this.stop,
    this.target,
    this.lots = 1.0,
    this.balance = 10000.0,
    this.rangeMultiple = 1.0,
    this.targetR = 2.0,
  });

  final String symbol;
  final TradeDirection direction;

  /// The price the setup wants. The engine fills at the first bar that trades through it.
  final double entry;

  /// The invalidation price. Always required — a setup with no stop is not a setup this app will
  /// score, because without it there is no R and no account-risk number to show.
  final double stop;

  /// The take-profit. Optional: a trader testing "what if I let it run to the end of the series"
  /// gets [target] == null and the result is marked unresolved rather than invented.
  final double? target;

  final double lots;

  /// Starting balance, used only to turn a result into an account-risk percentage. Defaults to a
  /// round 10k so the offline demo reads plausibly; the live screen passes the account balance.
  final double balance;

  /// How many bar-ranges wide the stop is, when this setup came from a bar.
  ///
  /// Carried on the setup rather than recomputed from [entry] and [stop], because the form restores the
  /// SLIDER position from it. Without it, moving the cursor to a new bar would have to guess the
  /// multiplier, and the slider would jump to a position the trader never chose.
  final double rangeMultiple;

  /// The R multiple the target sits at.
  ///
  /// Carried for the same reason as [rangeMultiple]: the selector shows a chosen R, and re-deriving it
  /// from fresh prices would silently move a level the trader set by hand.
  final double targetR;

  bool get isLong => direction == TradeDirection.long;

  /// Price distance from entry to stop. Always positive.
  double get riskDistance => (entry - stop).abs();

  /// Stop in pips. Null when the levels are unusable, so the UI can say why rather than show 0.
  double? get riskPips {
    if (entry <= 0 || stop <= 0 || riskDistance <= 0) return null;
    return TradingMath.pipsBetween(symbol, entry, stop);
  }

  /// Money at risk on this setup. Null when the stop cannot be read, which is what makes R undefined.
  double? get riskAmount {
    final double? pips = riskPips;
    if (pips == null || lots <= 0) return null;
    return TradingMath.riskAmount(symbol: symbol, stopPips: pips, lots: lots);
  }

  /// Reward:risk of the setup, or null when there is no target.
  ///
  /// [TradingMath.rewardRisk] is deliberately NOT used here: it requires a target, and this feature
  /// must support a setup with none.
  double? get rewardRisk {
    final double? tp = target;
    if (tp == null || riskDistance <= 0) return null;
    return double.parse(((tp - entry).abs() / riskDistance).toStringAsFixed(2));
  }

  /// What is wrong with this setup, or null when it is usable.
  ///
  /// Checked here rather than inside the engine so the form can refuse to run and name the level
  /// that is wrong. A replay that silently accepted a stop above the entry on a long and reported
  /// "-1R" would be a number no trader could interpret.
  String? get validationError {
    if (symbol.trim().isEmpty) return 'Pick a symbol to replay.';
    if (!(entry > 0) || !(stop > 0)) return 'Entry and stop must both be above zero.';
    if (riskDistance <= 0) return 'Entry and stop cannot be the same price.';
    if (isLong && stop >= entry) {
      return 'A long stop must sit BELOW the entry.';
    }
    if (!isLong && stop <= entry) {
      return 'A short stop must sit ABOVE the entry.';
    }
    if (target != null && rewardRisk == null) {
      return 'The target cannot sit on the stop.';
    }
    return null;
  }

  /// True when this setup can be replayed.
  bool get isValid => validationError == null;

  /// Signed money move for a fill at [price]. Negative means a loss.
  ///
  /// Pip math, not a raw price delta: a 0.10 move is 10 pips of gold and 1000 pips of EURUSD, and
  /// treating them alike is the easiest possible way to publish a backtest that is off by 100x.
  ///
  /// Expressed as `rBetween(entry, price) * riskAmount` rather than re-derived, so money and R on this
  /// screen can never disagree — and so the SIGN is handled in exactly one place.
  double pnlAt(double price) {
    final double? risk = riskAmount;
    final double? r = rBetween(entry, price);
    if (risk == null || r == null) return 0;
    return r * risk;
  }

  /// R multiple of a fill at [price], measured from [entry]. Null when the stop cannot be read.
  ///
  /// Delegates to [rBetween] so the entry-relative and fill-relative R figures come from one
  /// calculation. Two implementations of the same conversion is how a card ends up printing "-1.00R"
  /// beside a fill that the chart shows as a winner.
  double? rAt(double price) => rBetween(entry, price);

  /// Share of [balance] the stop would cost, as a percentage. Null when the stop cannot be read.
  ///
  /// This is the number that matters to a prop trader: not "the backtest made 2R" but "the stop on
  /// this setup was 0.8% of the account".
  double? get accountRiskPct {
    final double? risk = riskAmount;
    if (risk == null || balance <= 0) return null;
    return double.parse(((risk / balance) * 100).toStringAsFixed(2));
  }

  /// Whether the target was explicitly removed, which [copyWith] can express but `targetR` cannot.
  bool get hasTarget => target != null;

  /// Builds a setup around a price, with the stop at [range] away from it.
  ///
  /// The point of this factory is that a trader tapping a bar on the chart gets a stop the market
  /// itself defined — one bar-range away from the close — instead of having to invent three prices
  /// before they can see anything at all.
  factory ReplaySetup.around({
    required String symbol,
    required TradeDirection direction,
    required double referencePrice,
    required double range,
    double targetR = 2.0,
    double lots = 1.0,
    double balance = 10000.0,
  }) {
    final double stopDistance = range > 0 ? range : referencePrice * 0.01;
    final bool long = direction == TradeDirection.long;
    final double stop = long ? referencePrice - stopDistance : referencePrice + stopDistance;
    return ReplaySetup(
      symbol: symbol,
      direction: direction,
      entry: referencePrice,
      stop: stop,
      target: long
          ? referencePrice + (stopDistance * targetR)
          : referencePrice - (stopDistance * targetR),
      lots: lots,
      balance: balance,
      rangeMultiple: 1.0,
      targetR: targetR,
    );
  }

  /// R between two prices, for any pair of levels rather than entry→exit.
  ///
  /// Exists because a replay measures excursions from the FILL, which a gap can place away from
  /// [entry], and because MFE/MAE are R from fill to a running best/worst — not from the requested
  /// levels. All of it goes through [TradingMath], so there is exactly one pip definition in the app.
  double? rBetween(double from, double to) {
    final double? risk = riskAmount;
    if (risk == null || risk <= 0) return null;

    // SIGN MATTERS, AND IT HAS TWO PARTS. `TradingMath.pipsBetween` returns an ABSOLUTE distance, so it
    // cannot supply the sign at all — and an MAE that comes back positive is exactly the bug that makes
    // a risky setup look safe. The sign is therefore built from BOTH:
    //
    //   * whether price ROSE or FELL between [from] and [to]  (`delta`), and
    //   * which way the position is betting                        (`isLong`).
    //
    // A long wants price up; a short wants price down. Getting either factor wrong flips a drawdown into
    // a gain, so both are applied explicitly rather than folded into a single `isLong ? 1 : -1`.
    final double delta = to - from;
    if (delta == 0) return 0;

    final double pips = TradingMath.pipsBetween(symbol, 0, delta.abs());
    final double direction = isLong ? 1 : -1;
    final double move = delta > 0 ? 1 : -1;
    final double r = (pips * TradingMath.pipValue(symbol) * lots * direction * move) / risk;
    if (!r.isFinite) return null;
    return double.parse(r.toStringAsFixed(2));
  }

  /// Immutable update. `clearTarget` exists because `copyWith(target: null)` cannot otherwise
  /// express "remove the target" — and a setup without a target is a real, supported state.
  ReplaySetup copyWith({
    String? symbol,
    TradeDirection? direction,
    double? entry,
    double? stop,
    double? target,
    bool clearTarget = false,
    double? lots,
    double? balance,
    double? rangeMultiple,
    double? targetR,
  }) =>
      ReplaySetup(
        symbol: symbol ?? this.symbol,
        direction: direction ?? this.direction,
        entry: entry ?? this.entry,
        stop: stop ?? this.stop,
        target: clearTarget ? null : (target ?? this.target),
        lots: lots ?? this.lots,
        balance: balance ?? this.balance,
        rangeMultiple: rangeMultiple ?? this.rangeMultiple,
        targetR: targetR ?? this.targetR,
      );

  @override
  String toString() =>
      'ReplaySetup($symbol ${isLong ? 'long' : 'short'} $entry/$stop'
      '${target == null ? '' : '/$target'})';
}