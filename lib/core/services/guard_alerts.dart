import '../models/account.dart';
import '../models/guard_status.dart';

/// Thresholds that earn a push notification.
enum GuardAlertLevel { warn, critical, breach }

/// Decides when a threshold has been *crossed*.
///
/// Comparing against the previous reading — rather than "is it above now" — is what stops a
/// trader sitting above 70% from getting a push on every one-minute refresh. Comparing with `>=`
/// also means equity recovering below a threshold automatically re-arms that alert.
class GuardAlertEvaluator {
  const GuardAlertEvaluator({
    this.warnAt = 70,
    this.criticalAt = 90,
    this.breachAt = 100,
  });

  final double warnAt;
  final double criticalAt;
  final double breachAt;

  /// Returns at most one level: the highest newly-crossed threshold. A jump straight from safe to
  /// critical alerts once (critical), not twice (warn + critical). Every level is edge-triggered,
  /// so a 1/min refresh while a trader sits in breach stays quiet instead of spamming.
  List<GuardAlertLevel> evaluate({
    required GuardStatus current,
    GuardStatus? previous,
  }) {
    final double now = current.dailyUsedPct;
    final double before = previous?.dailyUsedPct ?? 0;

    final bool breachNow = current.state == GuardState.breach || now >= breachAt;
    final bool breachBefore =
        previous?.state == GuardState.breach || before >= breachAt;
    if (breachNow && !breachBefore) {
      return const <GuardAlertLevel>[GuardAlertLevel.breach];
    }
    if (now >= criticalAt && before < criticalAt) {
      return const <GuardAlertLevel>[GuardAlertLevel.critical];
    }
    if (now >= warnAt && before < warnAt) {
      return const <GuardAlertLevel>[GuardAlertLevel.warn];
    }
    return const <GuardAlertLevel>[];
  }
}

/// Push copy. Deliberately factual — it reports the number and never advises on a trade, which
/// keeps us inside the "analytics and education only" wording used across the app.
class GuardAlertCopy {
  GuardAlertCopy._();

  static String title(GuardAlertLevel level) => switch (level) {
        GuardAlertLevel.warn => 'Loss limit 70% used',
        GuardAlertLevel.critical => 'Loss limit 90% used',
        GuardAlertLevel.breach => 'Guard breach',
      };

  static String body(GuardAlertLevel level, TradingAccount account) =>
      switch (level) {
        GuardAlertLevel.warn =>
          '${account.nickname} has used 70% of today\'s loss limit.',
        GuardAlertLevel.critical =>
          '${account.nickname} has used 90% of today\'s loss limit.',
        GuardAlertLevel.breach =>
          '${account.nickname} reached its limit. Open TradeGuard to review.',
      };
}
