import '../../../core/models/signal.dart';
import 'volatility_score.dart';

/// Verified stats over closed signals: "what the posted calls did".
///
/// Every figure is derived from the rows the repository returned — this class
/// only *recombines* them (counting, summing, weighting by nothing but the
/// rows themselves). It never reaches back to trades, prices or the journal,
/// so there is exactly one place where a signal-stat number is defined.
///
/// Three facts are deliberately absent, and the UI must say so rather than
/// fill them in:
///   * **Win rate below the reporting floor is not stated.** A handful of
///     closed calls cannot support a rate, and printing one would invite the
///     reader to treat it as a measured edge. Below [minimumClosed] the stats
///     report the sample size and no rate at all — the same rule, and the same
///     reason, as `LeakDetector` and `ReplayScan`.
///   * **Open calls never count as wins, losses or pips.** An active signal is
///     risk still held, not a result. Counting it either way would flatter or
///     punish the ledger for something that has not happened yet.
///   * **Cancelled calls never count at all.** A call that was withdrawn
///     before it could resolve is not a trade, and treating it as a loss
///     would make a selective desk look like it missed money.
///
/// The single cross-domain member is [volatility], and its boundary is
/// deliberate: the ledger still never *derives* anything from prices —
/// `SignalStats.of` cannot see a bar. The radar score is computed from bars
/// by `VolatilityScore.of` and ATTACHED here as a separate observation,
/// always optional and null until a usable series exists, so the stats and
/// the radar can be rendered from one state object without the ledger ever
/// claiming the market produced its numbers.
class SignalStats {
  const SignalStats({
    required this.total,
    required this.active,
    required this.closed,
    required this.wins,
    required this.losses,
    required this.netPips,
    required this.avgPips,
    this.volatility,
  });

  /// Minimum closed calls before a win rate may be stated. Ten, not five: a
  /// signal ledger is a small, hand-picked sample and a rate off three calls
  /// is not a weak statistic, it is a misleading one.
  static const int minimumClosed = 10;

  /// Empty set, used for the no-signal and error states.
  static const SignalStats empty = SignalStats(
    total: 0,
    active: 0,
    closed: 0,
    wins: 0,
    losses: 0,
    netPips: 0,
    avgPips: null,
  );

  /// Every signal the repository returned.
  final int total;

  /// Still open. Shown as "live calls", never as results.
  final int active;

  /// Resolved with a pip figure: `closed` status AND a non-null `resultPips`.
  /// A closed call with no recorded result is honest missing data, not a zero.
  final int closed;

  /// Closed calls with a positive result.
  final int wins;

  /// Closed calls with a negative result. Breakeven (exactly 0) is neither.
  final int losses;

  /// Sum of `resultPips` over closed calls.
  final double netPips;

  /// Mean pips per closed call. Null when [closed] is zero, so "no closed
  /// calls" and "closed calls netted zero" cannot look alike.
  final double? avgPips;

  /// The volatility radar reading for the market bars behind this feed.
  ///
  /// Null until a usable bar series has been measured — and the UI must
  /// render that as "not measured", never as a score of 0 (which would read
  /// as "market dead calm"). Attached via [withVolatility]; `of` never sets
  /// it, because the ledger does not read prices.
  final VolatilityScore? volatility;

  /// Returns a copy of these stats with [value] attached.
  ///
  /// Every ledger figure is passed through untouched: the radar and the
  /// ledger are two observations shown side by side, and neither may
  /// recompute the other. This is also why it is `with…` rather than a
  /// setter — `SignalStats` stays immutable once built.
  SignalStats withVolatility(VolatilityScore? value) => SignalStats(
        total: total,
        active: active,
        closed: closed,
        wins: wins,
        losses: losses,
        netPips: netPips,
        avgPips: avgPips,
        volatility: value,
      );

  /// Closed calls behind the ledger — the honest sample size for every claim.
  int get sampleSize => closed;

  /// Whether the ledger is big enough to state a win rate. Below the floor
  /// the screen prints the sample size and no rate at all.
  bool get hasReportableRate => closed >= minimumClosed;

  /// Share of closed calls that won, as a 0…100 percentage. Null below the
  /// reporting floor, so a caller cannot accidentally render a rate the
  /// ledger cannot support.
  double? get winRate =>
      hasReportableRate ? (wins / closed) * 100 : null;

  /// Builds stats from the rows the repository returned. Pure, deterministic,
  /// and total: an empty input yields [empty] rather than throwing, because
  /// "no signals posted" is a state the UI must render, not an error.
  static SignalStats of(List<Signal> signals) {
    if (signals.isEmpty) return empty;
    int active = 0;
    int closed = 0;
    int wins = 0;
    int losses = 0;
    double netPips = 0;
    for (final Signal s in signals) {
      if (s.status == SignalStatus.active) {
        active++;
        continue;
      }
      final double? pips = s.resultPips;
      if (s.status != SignalStatus.closed || pips == null) continue;
      closed++;
      netPips += pips;
      if (pips > 0) {
        wins++;
      } else if (pips < 0) {
        losses++;
      }
    }
    return SignalStats(
      total: signals.length,
      active: active,
      closed: closed,
      wins: wins,
      losses: losses,
      netPips: netPips,
      avgPips: closed == 0 ? null : netPips / closed,
    );
  }

  @override
  String toString() => 'SignalStats(total=$total, active=$active, '
      'closed=$closed, wins=$wins, losses=$losses, netPips=$netPips, '
      'volatility=${volatility?.score})';
}
