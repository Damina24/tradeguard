import 'dart:math' as math;

/// All trading math lives here so it can be unit tested without Flutter.
class TradingMath {
  TradingMath._();

  /// Standard-lot pip value for a symbol. XAUUSD 1 lot = $10 per 0.1 move (100 pips).
  static double pipValue(String symbol) {
    final String s = symbol.toUpperCase();
    if (s.startsWith('XAU')) return 10.0; // gold: $10 per standard lot per pip
    if (s.contains('JPY')) return 9.0;
    if (s.startsWith('XAG')) return 50.0;
    return 10.0; // default USD pair
  }

  /// Pips between two prices for a symbol.
  static double pipsBetween(String symbol, double from, double to) {
    final String s = symbol.toUpperCase();
    final double factor = s.startsWith('XAU')
        ? 10.0 // 1 gold pip = $0.10
        : (s.contains('JPY') ? 100.0 : 10000.0);
    return (to - from).abs() * factor;
  }

  /// Risk-based position size in lots.
  ///
  /// lots = (balance * riskPct) / (stopPips * pipValuePerLot)
  static double lotSize({
    required double balance,
    required double riskPct,
    required String symbol,
    required double stopPips,
  }) {
    if (stopPips <= 0 || balance <= 0 || riskPct <= 0) return 0;
    final double riskAmount = balance * (riskPct / 100.0);
    final double perLot = stopPips * pipValue(symbol);
    return double.parse((riskAmount / perLot).toStringAsFixed(2));
  }

  /// Reward-to-risk ratio.
  static double rewardRisk({
    required double entry,
    required double stop,
    required double target,
  }) {
    final double risk = (entry - stop).abs();
    final double reward = (target - entry).abs();
    if (risk == 0) return 0;
    return double.parse((reward / risk).toStringAsFixed(2));
  }

  /// Money at risk for a given size.
  static double riskAmount({
    required String symbol,
    required double stopPips,
    required double lots,
  }) =>
      stopPips * pipValue(symbol) * lots;

  /// Daily loss percentage used for guard thresholds.
  static double dailyLossPct({
    required double dailyPnl,
    required double dailyLossLimit,
  }) {
    if (dailyLossLimit <= 0) return 0;
    final double used = dailyPnl < 0 ? -dailyPnl : 0;
    return double.parse(((used / dailyLossLimit) * 100).toStringAsFixed(1));
  }

  /// Distance (in currency) to the drawdown limit. Zero when breached.
  static double drawdownDistance({
    required double initialBalance,
    required double peakEquity,
    required double equity,
    required double maxDrawdown,
    required bool trailing,
  }) {
    final double reference = trailing ? peakEquity : initialBalance;
    final double floor = reference - maxDrawdown;
    return math.max(0, equity - floor);
  }

  /// Percentage toward the profit target (0..100+).
  static double targetProgressPct({
    required double initialBalance,
    required double equity,
    required double profitTarget,
  }) {
    if (profitTarget <= 0) return 0;
    final double profit = equity - initialBalance;
    return double.parse(((profit / profitTarget) * 100).toStringAsFixed(1));
  }

  /// Margin required for a position (USD account approximation).
  static double marginRequired({
    required double lots,
    required double price,
    required double leverage,
    required String symbol,
  }) {
    if (leverage <= 0) return 0;
    final double contractSize = symbol.toUpperCase().startsWith('XAU')
        ? 100.0
        : 100000.0;
    return (contractSize * lots * price) / leverage;
  }

  /// Position size that survives a given drawdown budget.
  static double safeLotsForDrawdown({
    required double drawdownBudget,
    required String symbol,
    required double stopPips,
  }) {
    final double perLot = stopPips * pipValue(symbol);
    if (perLot <= 0) return 0;
    return double.parse((drawdownBudget / perLot).toStringAsFixed(2));
  }
}
