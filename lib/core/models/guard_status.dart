import '../utils/trading_math.dart';
import 'account.dart';

enum GuardState { ok, warn, critical, breach, stale, error }

extension GuardStateX on GuardState {
  String get label => switch (this) {
        GuardState.ok => 'SAFE',
        GuardState.warn => 'WATCH',
        GuardState.critical => 'DANGER',
        GuardState.breach => 'BREACHED',
        GuardState.stale => 'STALE',
        GuardState.error => 'OFFLINE',
      };
}

/// Derived guard numbers for one account at a point in time.
class GuardStatus {
  const GuardStatus({
    required this.account,
    required this.dailyUsedPct,
    required this.dailyLeft,
    required this.dailyLossLimit,
    required this.drawdownDistance,
    required this.maxDrawdown,
    required this.targetLeftPct,
    required this.state,
    required this.asOf,
  });

  final TradingAccount account;
  final double dailyUsedPct;
  final double dailyLeft;
  final double dailyLossLimit;
  final double drawdownDistance;
  final double maxDrawdown;
  final double targetLeftPct;
  final GuardState state;
  final DateTime asOf;

  bool get isStale => DateTime.now().difference(asOf).inMinutes > 3;

  static GuardStatus compute(TradingAccount a, {DateTime? now}) {
    final double used = TradingMath.dailyLossPct(
      dailyPnl: a.dailyPnl,
      dailyLossLimit: a.dailyLossLimit,
    );
    final double ddDistance = TradingMath.drawdownDistance(
      initialBalance: a.initialBalance,
      peakEquity: a.peakEquity == 0 ? a.initialBalance : a.peakEquity,
      equity: a.equity,
      maxDrawdown: a.maxDrawdown,
      trailing: a.drawdownType == DrawdownType.trailing,
    );
    final double targetPct = TradingMath.targetProgressPct(
      initialBalance: a.initialBalance,
      equity: a.equity,
      profitTarget: a.profitTarget,
    );

    GuardState state;
    if (ddDistance <= 0 || used >= 100) {
      state = GuardState.breach;
    } else if (used >= 90) {
      state = GuardState.critical;
    } else if (used >= 70) {
      state = GuardState.warn;
    } else {
      state = GuardState.ok;
    }

    return GuardStatus(
      account: a,
      dailyUsedPct: used,
      dailyLeft: (a.dailyLossLimit - (a.dailyPnl < 0 ? -a.dailyPnl : 0))
          .clamp(0, double.infinity)
          .toDouble(),
      dailyLossLimit: a.dailyLossLimit,
      drawdownDistance: ddDistance,
      maxDrawdown: a.maxDrawdown,
      targetLeftPct: (100 - targetPct).clamp(0, 100).toDouble(),
      state: state,
      asOf: now ?? DateTime.now(),
    );
  }
}
