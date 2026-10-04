import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/account.dart';
import 'package:tradeguard/core/models/guard_status.dart';

void main() {
  TradingAccount account({
    double equity = 100000,
    double peak = 100000,
    double dailyPnl = 0,
    DrawdownType dd = DrawdownType.trailing,
  }) =>
      TradingAccount(
        id: 'a',
        nickname: 'EVAL',
        platform: 'mt5',
        phase: AccountPhase.eval,
        currency: 'USD',
        initialBalance: 100000,
        profitTarget: 10000,
        dailyLossLimit: 5000,
        maxDrawdown: 10000,
        drawdownType: dd,
        equity: equity,
        balance: equity,
        dailyPnl: dailyPnl,
        peakEquity: peak,
      );

  group('GuardStatus thresholds', () {
    test('safe when nothing used', () {
      final GuardStatus s = GuardStatus.compute(account());
      expect(s.state, GuardState.ok);
      expect(s.dailyUsedPct, 0);
    });

    test('warn at 70% daily loss', () {
      final GuardStatus s = GuardStatus.compute(account(dailyPnl: -3500));
      expect(s.state, GuardState.warn);
    });

    test('critical at 90% daily loss', () {
      final GuardStatus s = GuardStatus.compute(account(dailyPnl: -4600));
      expect(s.state, GuardState.critical);
    });

    test('breach at 100% daily loss', () {
      final GuardStatus s = GuardStatus.compute(account(dailyPnl: -5000));
      expect(s.state, GuardState.breach);
    });

    test('breach when trailing floor is hit', () {
      final GuardStatus s = GuardStatus.compute(
        account(equity: 89000, peak: 100000),
      );
      expect(s.state, GuardState.breach);
      expect(s.drawdownDistance, 0);
    });

    test('dailyLeft never negative', () {
      final GuardStatus s = GuardStatus.compute(account(dailyPnl: -9000));
      expect(s.dailyLeft, 0);
    });
  });
}
