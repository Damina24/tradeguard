/// The numeric bars a leak must clear before it is reported.
///
/// These are thresholds for *reporting confidence*, not trading advice, and they
/// live in one place so the numbers governing "is this a leak" are visible rather
/// than scattered through the detector.
///
/// Defaults are deliberately conservative:
///   * under [minTrades] (5) nothing is reported at all — five closed trades is
///     too few to call a slice a habit, and one bad trade must never qualify;
///   * [lossShare] (0.40) for a concentration leak, so a slice has to account for
///     a clear plurality of losses rather than edging ahead on a small total;
///   * the confidence tiers are monotonic, so a label can never outrun the gate.
class LeakThresholds {
  const LeakThresholds({
    this.minTrades = 5,
    this.moderateTrades = 20,
    this.highTrades = 50,
    this.lossShare = 0.40,
  });

  /// Fewest trades a slice needs before it can be reported as a leak at all.
  final int minTrades;

  /// Fewest trades before a leak stops being called a "small sample".
  final int moderateTrades;

  /// Fewest trades before a leak is called a "large sample".
  final int highTrades;

  /// Fraction of the trader's total losses a single slice must account for to be
  /// flagged as a concentration leak.
  final double lossShare;
}