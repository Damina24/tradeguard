import 'replay_setup.dart';

/// How a replay ended.
///
/// The distinction between [targetHit], [stopHit] and [unresolved] is the whole point of this
/// feature, so each is a separate value rather than a nullable `won` flag:
///
///   * [notFilled] — price never traded through the entry. Nothing happened. **Never** counted as a
///     loss in [ReplayScan]; pretending a setup that never triggered cost money would understate it.
///   * [targetHit] / [stopHit] — the trade resolved, and the bar range says which level did it.
///   * [unresolved] — it filled and neither level was reached before the series ran out. The position
///     is marked to the last close and labelled incomplete, because "still open at the end of the
///     data" is a real and materially different outcome from "lost".
///   * [invalid] — the setup itself could not be scored (see [ReplaySetup.validationError]).
enum ReplayStatus { notFilled, targetHit, stopHit, unresolved, invalid }

/// One replayed setup, bar by bar.
///
/// Immutable, and it carries the *evidence* for its verdict (which bar filled, which bar exited,
/// how far it went against and with the position) rather than only the number. A backtest result a
/// trader cannot audit bar by bar is indistinguishable from marketing.
class ReplayResult {
  const ReplayResult({
    required this.setup,
    required this.status,
    this.fillIndex,
    this.fillPrice,
    this.exitIndex,
    this.exitPrice,
    this.barsHeld,
    this.mfeR,
    this.maeR,
  });

  /// The setup was not scorable.
  factory ReplayResult.invalid(ReplaySetup setup) => ReplayResult(
        setup: setup,
        status: ReplayStatus.invalid,
      );

  /// Price never traded through the entry.
  factory ReplayResult.notFilled(ReplaySetup setup) => ReplayResult(
        setup: setup,
        status: ReplayStatus.notFilled,
      );

  final ReplaySetup setup;
  final ReplayStatus status;

  /// Index into the bar list where the entry filled, or null when it did not.
  final int? fillIndex;

  /// Price the entry actually filled at.
  ///
  /// Can differ from [ReplaySetup.entry] when the series **gapped** straight through it — a bar
  /// that opened beyond the entry fills at its open, which is the only price that existed. A replay
  /// that filled every entry at the requested price would report profits no trader could have got.
  final double? fillPrice;

  final int? exitIndex;
  final double? exitPrice;

  /// Bars between fill and exit. Zero means the position never survived its own entry bar.
  final int? barsHeld;

  /// Maximum favourable excursion, in R — the best the trade got. Null when it never filled.
  final double? mfeR;

  /// Maximum adverse excursion, in R — the worst it got, in the same R units. A negative number.
  ///
  /// This is the number that catches the quiet failure mode: a setup whose MAE routinely runs past
  /// -1R would have been stopped out on a live account long before its target arrived.
  final double? maeR;

  /// True when the position actually traded.
  bool get didFill => fillIndex != null;

  /// True when the setup reached a conclusion inside the data.
  bool get isResolved =>
      status == ReplayStatus.targetHit || status == ReplayStatus.stopHit;

  /// Result in R, or null when the trade never filled.
  ///
  /// For [ReplayStatus.unresolved] this is the mark-to-market R at the final close, and it is
  /// deliberately a number rather than null — hiding it would make an open trade look identical to
  /// a setup that never triggered. The STATUS is what tells the two apart on screen.
  double? get rMultiple {
    final double? price = exitPrice;
    if (price == null) return null;
    return setup.rAt(price);
  }

  /// Money result, or null when the trade never filled.
  double? get pnl {
    final double? price = exitPrice;
    if (price == null) return null;
    return setup.pnlAt(price);
  }

  /// R at the best point reached. Null when the trade never filled.
  double? get bestR => mfeR;

  /// R at the worst point reached. Null when the trade never filled.
  double? get worstR => maeR;

  /// Whether this outcome should count as a win in an aggregate.
  ///
  /// Only [ReplayStatus.targetHit]. A stop is a loss, an unresolved position is unknown, and a setup
  /// that never filled is not a trade at all.
  bool get isWin => status == ReplayStatus.targetHit;

  /// Whether this outcome counts as a loss in an aggregate.
  bool get isLoss => status == ReplayStatus.stopHit;

  /// Whether the trade traded at all. The denominator question every aggregate must ask first.
  bool get countsAsTrade =>
      status == ReplayStatus.targetHit ||
      status == ReplayStatus.stopHit ||
      status == ReplayStatus.unresolved;

  @override
  String toString() =>
      'ReplayResult(${status.name} r=${rMultiple?.toStringAsFixed(2)})';
}