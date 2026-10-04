import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/utils/trading_math.dart';

void main() {
  group('pipValue', () {
    test('gold pip value is 10 per lot', () {
      expect(TradingMath.pipValue('XAUUSD'), 10.0);
    });

    test('default fx pip value is 10', () {
      expect(TradingMath.pipValue('EURUSD'), 10.0);
    });

    test('silver pip value is 50', () {
      expect(TradingMath.pipValue('XAGUSD'), 50.0);
    });
  });

  group('lotSize', () {
    test('10000 balance, 1% risk, 20 pip stop on gold = 0.5 lots', () {
      final double lots = TradingMath.lotSize(
        balance: 10000,
        riskPct: 1,
        symbol: 'XAUUSD',
        stopPips: 20,
      );
      // risk = 100; perLot = 20 * 10 = 200; lots = 0.5
      expect(lots, 0.5);
    });

    test('zero stop returns zero', () {
      expect(
        TradingMath.lotSize(balance: 10000, riskPct: 1, symbol: 'EURUSD', stopPips: 0),
        0,
      );
    });
  });

  group('rewardRisk', () {
    test('2:1 ratio computed correctly', () {
      expect(
        TradingMath.rewardRisk(entry: 100, stop: 90, target: 120),
        2.0,
      );
    });

    test('zero risk returns zero', () {
      expect(TradingMath.rewardRisk(entry: 100, stop: 100, target: 120), 0);
    });
  });

  group('dailyLossPct', () {
    test('half the limit used equals 50%', () {
      expect(
        TradingMath.dailyLossPct(dailyPnl: -2500, dailyLossLimit: 5000),
        50.0,
      );
    });

    test('profit does not consume the limit', () {
      expect(
        TradingMath.dailyLossPct(dailyPnl: 800, dailyLossLimit: 5000),
        0,
      );
    });
  });

  group('drawdownDistance', () {
    test('trailing uses peak equity', () {
      final double d = TradingMath.drawdownDistance(
        initialBalance: 100000,
        peakEquity: 105000,
        equity: 103000,
        maxDrawdown: 10000,
        trailing: true,
      );
      // floor = 95000; distance = 103000 - 95000 = 8000
      expect(d, 8000);
    });

    test('breached returns zero not negative', () {
      final double d = TradingMath.drawdownDistance(
        initialBalance: 100000,
        peakEquity: 100000,
        equity: 89000,
        maxDrawdown: 10000,
        trailing: false,
      );
      expect(d, 0);
    });
  });

  group('targetProgress', () {
    test('50% of target reached', () {
      expect(
        TradingMath.targetProgressPct(
          initialBalance: 100000,
          equity: 105000,
          profitTarget: 10000,
        ),
        50.0,
      );
    });
  });

  group('pipsBetween', () {
    test('gold 2345.50 -> 2338.00 is 75 pips', () {
      expect(TradingMath.pipsBetween('XAUUSD', 2345.50, 2338.00), closeTo(75, 0.01));
    });
  });

  group('safeLotsForDrawdown', () {
    test('500 budget / 20 pips gold = 2.5 lots', () {
      expect(
        TradingMath.safeLotsForDrawdown(
          drawdownBudget: 500,
          symbol: 'XAUUSD',
          stopPips: 20,
        ),
        2.5,
      );
    });
  });
}
