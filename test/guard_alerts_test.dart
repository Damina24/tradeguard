import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/account.dart';
import 'package:tradeguard/core/models/guard_status.dart';
import 'package:tradeguard/core/services/guard_alert_monitor.dart';
import 'package:tradeguard/core/services/guard_alerts.dart';
import 'package:tradeguard/core/services/push_service.dart';

/// Daily loss limit used by the fixtures. `usedPct` maps to `dailyPnl` via
/// TradingMath.dailyLossPct = |pnl| / limit * 100.
const double _limit = 1000;

TradingAccount _account({required String id, required double usedPct}) =>
    TradingAccount(
      id: id,
      nickname: 'TEST 100K',
      platform: 'mt5',
      phase: AccountPhase.eval,
      currency: 'USD',
      initialBalance: 100000,
      profitTarget: 8000,
      dailyLossLimit: _limit,
      maxDrawdown: 10000,
      drawdownType: DrawdownType.static,
      equity: 100000 - (usedPct / 100 * _limit),
      balance: 100000,
      dailyPnl: -(usedPct / 100 * _limit),
      peakEquity: 100000,
    );

GuardStatus _status(double usedPct, {String id = 'acc_x'}) =>
    GuardStatus.compute(_account(id: id, usedPct: usedPct));

/// Broadcast streams deliver asynchronously, so drain the event queue before asserting.
Future<void> _feed(GuardAlertMonitor monitor, GuardStatus status) async {
  await monitor.onGuardStatus(status);
  await pumpEventQueue();
}

void main() {
  const GuardAlertEvaluator evaluator = GuardAlertEvaluator();

  group('GuardAlertEvaluator', () {
    test('stays silent below the warn threshold', () {
      expect(
        evaluator.evaluate(current: _status(20), previous: _status(10)),
        isEmpty,
      );
    });

    test('fires warn when crossing 70%', () {
      expect(
        evaluator.evaluate(current: _status(70), previous: _status(60)),
        <GuardAlertLevel>[GuardAlertLevel.warn],
      );
    });

    test('does not re-fire while staying above 70%', () {
      expect(
        evaluator.evaluate(current: _status(75), previous: _status(72)),
        isEmpty,
      );
    });

    test('re-arms once equity recovers below the threshold', () {
      expect(
        evaluator.evaluate(current: _status(71), previous: _status(65)),
        <GuardAlertLevel>[GuardAlertLevel.warn],
      );
    });

    test('a jump straight to 95% alerts once, at critical', () {
      expect(
        evaluator.evaluate(current: _status(95), previous: _status(60)),
        <GuardAlertLevel>[GuardAlertLevel.critical],
      );
    });

    test('100% is a breach and supersedes the lower levels', () {
      expect(
        evaluator.evaluate(current: _status(100), previous: _status(95)),
        <GuardAlertLevel>[GuardAlertLevel.breach],
      );
    });

    test('a sustained breach does not re-alert every refresh', () {
      expect(
        evaluator.evaluate(current: _status(100), previous: _status(100)),
        isEmpty,
      );
      expect(
        evaluator.evaluate(current: _status(104), previous: _status(100)),
        isEmpty,
      );
    });

    test('the first ever reading counts as a crossing', () {
      expect(
        evaluator.evaluate(current: _status(75)),
        <GuardAlertLevel>[GuardAlertLevel.warn],
      );
    });
  });

  group('GuardAlertCopy', () {
    test('warn names the account and the threshold', () {
      final TradingAccount account = _account(id: 'acc_x', usedPct: 70);
      expect(
        GuardAlertCopy.title(GuardAlertLevel.warn),
        'Loss limit 70% used',
      );
      expect(
        GuardAlertCopy.body(GuardAlertLevel.warn, account),
        contains('TEST 100K'),
      );
    });

    test('breach copy is factual and gives no trading advice', () {
      final TradingAccount account = _account(id: 'acc_x', usedPct: 100);
      final String body = GuardAlertCopy.body(GuardAlertLevel.breach, account);
      expect(body, contains('Open TradeGuard'));
      expect(body.toLowerCase(), isNot(contains('buy')));
      expect(body.toLowerCase(), isNot(contains('sell')));
    });
  });

  group('GuardAlertMonitor', () {
    test('subscribes to the account topic once, on first reading', () async {
      final MockPushService push = MockPushService();
      final GuardAlertMonitor monitor = GuardAlertMonitor(push: push);
      addTearDown(monitor.dispose);

      await _feed(monitor, _status(10, id: 'acc_a'));
      expect(push.subscriptions, <String>['acc_a']);

      await _feed(monitor, _status(20, id: 'acc_a'));
      expect(push.subscriptions.length, 1);
    });

    test('raises one alert per crossing, not one per refresh', () async {
      final GuardAlertMonitor monitor = GuardAlertMonitor();
      addTearDown(monitor.dispose);
      final List<GuardAlert> alerts = <GuardAlert>[];
      addTearDown(monitor.alerts.listen(alerts.add).cancel);

      await _feed(monitor, _status(10));
      await _feed(monitor, _status(60));
      expect(alerts, isEmpty);

      await _feed(monitor, _status(72));
      expect(alerts.length, 1);
      expect(monitor.lastAlert?.level, GuardAlertLevel.warn);

      // A 1/min refresh while the trader sits above 70% must stay quiet.
      await _feed(monitor, _status(72));
      await _feed(monitor, _status(80));
      expect(alerts.length, 1);
    });

    test('escalates through critical to breach', () async {
      final GuardAlertMonitor monitor = GuardAlertMonitor();
      addTearDown(monitor.dispose);

      await monitor.onGuardStatus(_status(60));
      await monitor.onGuardStatus(_status(95));
      expect(monitor.lastAlert?.level, GuardAlertLevel.critical);

      await monitor.onGuardStatus(_status(100));
      expect(monitor.lastAlert?.level, GuardAlertLevel.breach);
      expect(monitor.lastAlert?.title, 'Guard breach');
      expect(monitor.lastAlert?.at, isNotNull);
    });

    test('switching to a safe account does not replay a stale breach', () async {
      final GuardAlertMonitor monitor = GuardAlertMonitor();
      addTearDown(monitor.dispose);
      final List<GuardAlert> alerts = <GuardAlert>[];
      addTearDown(monitor.alerts.listen(alerts.add).cancel);

      await _feed(monitor, _status(100, id: 'acc_a'));
      expect(alerts.length, 1);

      await _feed(monitor, _status(10, id: 'acc_b'));
      expect(alerts.length, 1);
    });

    test('reset re-arms every threshold', () async {
      final GuardAlertMonitor monitor = GuardAlertMonitor();
      addTearDown(monitor.dispose);
      final List<GuardAlert> alerts = <GuardAlert>[];
      addTearDown(monitor.alerts.listen(alerts.add).cancel);

      await _feed(monitor, _status(60));
      await _feed(monitor, _status(75));
      expect(alerts.length, 1);

      monitor.reset();
      expect(monitor.lastAlert, isNull);
      expect(monitor.previousStatus, isNull);

      await _feed(monitor, _status(75));
      expect(alerts.length, 2);
    });

    test('a sustained breach raises exactly one alert', () async {
      final GuardAlertMonitor monitor = GuardAlertMonitor();
      addTearDown(monitor.dispose);
      final List<GuardAlert> alerts = <GuardAlert>[];
      addTearDown(monitor.alerts.listen(alerts.add).cancel);

      await _feed(monitor, _status(100));
      await _feed(monitor, _status(100));
      await _feed(monitor, _status(104));

      expect(alerts.length, 1);
      expect(alerts.single.level, GuardAlertLevel.breach);
    });

    test('alert copy carries the account nickname', () async {
      final GuardAlertMonitor monitor = GuardAlertMonitor();
      addTearDown(monitor.dispose);

      await monitor.onGuardStatus(_status(75));
      expect(monitor.lastAlert?.body, contains('TEST 100K'));
    });
  });
}
