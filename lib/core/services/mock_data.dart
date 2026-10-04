import 'dart:math';

import '../../core/models/account.dart';
import '../../core/models/signal.dart';
import '../../core/models/trade.dart';

/// Deterministic seed data so the whole UI runs without any backend.
class MockData {
  MockData._();

  static TradingAccount evalAccount() => const TradingAccount(
        id: 'acc_eval_100k',
        nickname: 'FTMO EVAL 100K',
        platform: 'mt5',
        phase: AccountPhase.eval,
        currency: 'USD',
        initialBalance: 100000,
        profitTarget: 10000,
        dailyLossLimit: 5000,
        maxDrawdown: 10000,
        drawdownType: DrawdownType.trailing,
        equity: 103450,
        balance: 103450,
        dailyPnl: -1820,
        peakEquity: 105200,
        propFirm: 'FTMO',
        equityGuardEnabled: false,
      );

  static TradingAccount fundedAccount() => const TradingAccount(
        id: 'acc_funded_50k',
        nickname: 'FUNDED 50K',
        platform: 'mt5',
        phase: AccountPhase.funded,
        currency: 'USD',
        initialBalance: 50000,
        profitTarget: 5000,
        dailyLossLimit: 2500,
        maxDrawdown: 2500,
        drawdownType: DrawdownType.trailing,
        equity: 51820,
        balance: 51820,
        dailyPnl: 640,
        peakEquity: 52100,
        propFirm: 'FTMO',
        equityGuardEnabled: true,
      );

  static List<TradingAccount> accounts() =>
      <TradingAccount>[evalAccount(), fundedAccount()];

  static List<Trade> trades() {
    final Random rnd = Random(7);
    final List<Trade> out = <Trade>[];
    const List<String> symbols = <String>['XAUUSD', 'EURUSD', 'GBPUSD', 'US30'];
    const List<String> sessions = <String>['london', 'newyork', 'asia'];
    const List<String> setups = <String>['Breakout', 'Pullback', 'Reversal'];
    const List<String> grades = <String>['A', 'B', 'C', 'D'];
    final DateTime now = DateTime.now();

    for (int i = 0; i < 60; i++) {
      final double pnl = (rnd.nextDouble() * 900) - 320;
      final DateTime close = now.subtract(Duration(hours: i * 5 + 2));
      out.add(
        Trade(
          id: 't_$i',
          accountId: i.isEven ? 'acc_eval_100k' : 'acc_funded_50k',
          symbol: symbols[i % symbols.length],
          direction: rnd.nextBool() ? TradeDirection.long : TradeDirection.short,
          lots: double.parse((0.5 + rnd.nextDouble() * 2).toStringAsFixed(2)),
          pnl: double.parse(pnl.toStringAsFixed(2)),
          entry: double.parse((1.05 + rnd.nextDouble() * 0.1).toStringAsFixed(4)),
          exit: double.parse((1.05 + rnd.nextDouble() * 0.1).toStringAsFixed(4)),
          stop: double.parse((1.05 + rnd.nextDouble() * 0.1).toStringAsFixed(4)),
          target: double.parse((1.05 + rnd.nextDouble() * 0.1).toStringAsFixed(4)),
          openTime: close.subtract(const Duration(hours: 3)),
          closeTime: close,
          session: sessions[i % sessions.length],
          setup: setups[i % setups.length],
          grade: grades[i % grades.length],
          rMultiple: pnl >= 0
              ? double.parse((0.5 + rnd.nextDouble() * 2.5).toStringAsFixed(2))
              : double.parse((-1.0 + rnd.nextDouble() * 0.05).toStringAsFixed(2)),
        ),
      );
    }
    return out;
  }

  static List<Signal> signals() {
    final DateTime now = DateTime.now();
    return <Signal>[
      Signal(
        id: 's1',
        pair: 'XAUUSD',
        direction: SignalDirection.buy,
        entry: 2345.50,
        stop: 2338.00,
        tp1: 2358.00,
        tp2: 2366.50,
        tp3: 2375.00,
        confidence: 82,
        rationale:
            'London sweep of Asian low into daily support; DXY rolling over.',
        createdAt: now.subtract(const Duration(minutes: 12)),
        premium: true,
      ),
      Signal(
        id: 's2',
        pair: 'EURUSD',
        direction: SignalDirection.sell,
        entry: 1.0872,
        stop: 1.0905,
        tp1: 1.0825,
        tp2: 1.0790,
        confidence: 68,
        rationale: 'H4 lower-high rejection at prior resistance; bearish OB.',
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      Signal(
        id: 's3',
        pair: 'GBPJPY',
        direction: SignalDirection.buy,
        entry: 199.40,
        stop: 198.90,
        tp1: 200.35,
        tp2: 201.10,
        confidence: 74,
        rationale: 'Break and retest of London high; momentum alignment.',
        createdAt: now.subtract(const Duration(hours: 5)),
        status: SignalStatus.closed,
        resultPips: 95,
      ),
    ];
  }
}
