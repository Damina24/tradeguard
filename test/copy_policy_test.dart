import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/account.dart';
import 'package:tradeguard/core/models/copy_settings.dart';
import 'package:tradeguard/core/models/signal.dart';
import 'package:tradeguard/core/utils/trading_math.dart';
import 'package:tradeguard/features/signals/domain/copy_preview.dart';

/// Client half of the `copy-signal` contract.
///
/// The PARITY FIXTURES group is an IDENTICAL table to the one in
/// `supabase/functions/copy-signal/copy_signal_test.ts` — a formula change
/// that lands on one side only fails both suites. The remaining groups pin
/// the Dart mirrors (`CopySettings`, `CopyPreview.of`) to the server's
/// defaults and refusal vocabulary, so "the sheet previewed it" and "the
/// server placed it" stay the same statement.
void main() {
  // ── Fixtures ─────────────────────────────────────────────────────────────
  final Signal signal = Signal(
    id: '11111111-2222-3333-4444-555555555555',
    pair: 'XAUUSD',
    direction: SignalDirection.buy,
    entry: 2345.5,
    stop: 2338.0,
    tp1: 2358.0,
    confidence: 80,
    rationale: 'parity fixture',
    createdAt: DateTime.utc(2026, 1, 1),
  );

  TradingAccount account({double equity = 100000, String id = 'acc'}) =>
      TradingAccount(
        id: id,
        nickname: 'Fixture',
        platform: 'mt5',
        phase: AccountPhase.eval,
        currency: 'USD',
        initialBalance: equity,
        profitTarget: 0,
        dailyLossLimit: 0,
        maxDrawdown: 0,
        drawdownType: DrawdownType.static,
        equity: equity,
        balance: equity,
        dailyPnl: 0,
        peakEquity: equity,
        // Healthy means copyable: mirrors copy_signal_test.ts account() which
        // sets copyEnabled: true. The model default is false (migration 0009
        // column default), so omitting this would make every "healthy" fixture
        // refuse as accountDisabled before sizing is ever reached.
        copyEnabled: true,
      );

  // ── Parity fixtures — IDENTICAL table in copy_signal_test.ts ─────────────
  group('parity fixtures (identical to copy_signal_test.ts)', () {
    test('XAUUSD 75-pip stop, \$100k, 1% risk -> 1.33 lots', () {
      expect(
        TradingMath.lotSize(
          balance: 100000,
          riskPct: 1,
          symbol: 'XAUUSD',
          stopPips: 75,
        ),
        1.33,
      );
    });

    test('EURUSD 50-pip stop, \$50k, 2% risk -> 2.00 lots', () {
      expect(
        TradingMath.lotSize(
          balance: 50000,
          riskPct: 2,
          symbol: 'EURUSD',
          stopPips: 50,
        ),
        2,
      );
    });

    test('USDJPY 30-pip stop, \$10k, 0.5% risk -> 0.19 lots', () {
      expect(
        TradingMath.lotSize(
          balance: 10000,
          riskPct: 0.5,
          symbol: 'USDJPY',
          stopPips: 30,
        ),
        0.19,
      );
    });

    test('XAUUSD entry/stop distance uses the gold pip factor', () {
      // Float-noise-tolerant, same 1e-6 bound as the TS `near()`: pipsBetween
      // is pure IEEE-754 arithmetic and Dart produces the same last-bit noise.
      expect(
        TradingMath.pipsBetween('XAUUSD', 2345.5, 2338.0),
        closeTo(75, 1e-6),
      );
      expect(
        TradingMath.pipsBetween('EURUSD', 1.1000, 1.0950),
        closeTo(50, 1e-6),
      );
      expect(
        TradingMath.pipsBetween('USDJPY', 150.00, 149.70),
        closeTo(30, 1e-6),
      );
    });

    test('pip values match the documented table', () {
      expect(TradingMath.pipValue('XAUUSD'), 10);
      expect(TradingMath.pipValue('USDJPY'), 9);
      expect(TradingMath.pipValue('XAGUSD'), 50);
      expect(TradingMath.pipValue('EURUSD'), 10);
    });

    test('degenerate inputs size to zero, never negative', () {
      expect(
        TradingMath.lotSize(
          balance: 100000,
          riskPct: 1,
          symbol: 'XAUUSD',
          stopPips: 0,
        ),
        0,
      );
      expect(
        TradingMath.lotSize(
          balance: 100000,
          riskPct: 1,
          symbol: 'XAUUSD',
          stopPips: -5,
        ),
        0,
      );
      expect(
        TradingMath.lotSize(
          balance: 0,
          riskPct: 1,
          symbol: 'XAUUSD',
          stopPips: 75,
        ),
        0,
      );
      expect(
        TradingMath.lotSize(
          balance: 100000,
          riskPct: 0,
          symbol: 'XAUUSD',
          stopPips: 75,
        ),
        0,
      );
    });
  });


  // ── CopySettings — the DEFAULT_SETTINGS mirror ───────────────────────────
  group('CopySettings mirrors shared.ts DEFAULT_SETTINGS', () {
    test('defaults are the server quartet verbatim', () {
      expect(CopySettings.defaults.liveConsent, false);
      expect(CopySettings.defaults.killSwitch, false);
      expect(CopySettings.defaults.maxLots, 5.0);
      expect(CopySettings.defaults.maxConcurrentFollows, 5);
    });

    test('risk band and request caps match MIN/MAX/DEFAULT', () {
      expect(CopySettings.defaultRiskPct, 1.0);
      expect(CopySettings.minRiskPct, 0.25);
      expect(CopySettings.maxRiskPct, 5.0);
      expect(CopySettings.maxAccountsPerRequest, 10);
    });

    test('an absent row (empty json) reads as all-defaults', () {
      final CopySettings s = CopySettings.fromJson(const <String, dynamic>{});
      expect(s.liveConsent, false);
      expect(s.killSwitch, false);
      expect(s.maxLots, 5.0);
      expect(s.maxConcurrentFollows, 5);
    });

    test('a row round-trips through json', () {
      const Map<String, dynamic> row = <String, dynamic>{
        'live_consent': true,
        'kill_switch': true,
        'max_lots': 2.5,
        'max_concurrent_follows': 3,
      };
      expect(CopySettings.fromJson(row).toJson(), row);
    });

    test('clampRiskPct clamps instead of failing (parity with shared.ts)', () {
      expect(CopySettings.clampRiskPct(null), 1.0);
      expect(CopySettings.clampRiskPct(double.nan), 1.0);
      expect(CopySettings.clampRiskPct(0.01), 0.25);
      expect(CopySettings.clampRiskPct(99), 5.0);
      expect(CopySettings.clampRiskPct(1.234), 1.23);
      expect(CopySettings.clampRiskPct(2.5), 2.5);
    });
  });

  // ── CopyPreview — client-knowable half of evaluateAccount ────────────────
  group('CopyPreview ladder (mirrors evaluateAccount)', () {
    test('active signal on a healthy account sizes with no refusal', () {
      final CopyPreview p = CopyPreview.of(
        signal: signal,
        account: account(),
        riskPct: 1,
      );
      expect(p.refusal, isNull);
      expect(p.isPlaceable, isTrue);
      expect(p.lots, 1.33); // 100000 x 1% / (75 x $10)
      expect(p.riskPips, closeTo(75, 1e-6));
      // Max loss is the rounded size a broker would receive, not the
      // unrounded intent: 1.33 lots x 750 = $997.50.
      expect(p.maxLoss, closeTo(997.50, 1e-6));
    });

    test('a zero-width stop is invalidSignal, not a maximum-size order', () {
      final CopyPreview p = CopyPreview.of(
        signal: Signal(
          id: 'z',
          pair: 'XAUUSD',
          direction: SignalDirection.buy,
          entry: 2345.5,
          stop: 2345.5,
          tp1: 2358.0,
          confidence: 80,
          rationale: '',
          createdAt: DateTime.utc(2026),
        ),
        account: account(),
        riskPct: 1,
      );
      expect(p.refusal, CopyRefusal.invalidSignal);
      expect(p.riskPips, 0);
      expect(p.lots, 0);
      expect(p.maxLoss, 0);
    });

    test('a closed signal is inactiveSignal before any sizing', () {
      final CopyPreview p = CopyPreview.of(
        signal: Signal(
          id: 'c',
          pair: 'XAUUSD',
          direction: SignalDirection.buy,
          entry: 2345.5,
          stop: 2338.0,
          tp1: 2358.0,
          confidence: 80,
          rationale: '',
          createdAt: DateTime.utc(2026),
          status: SignalStatus.closed,
        ),
        account: account(),
        riskPct: 1,
      );
      expect(p.refusal, CopyRefusal.inactiveSignal);
      expect(p.lots, 0);
    });

    test('lots over the cap are refused, not silently clamped', () {
      final CopyPreview p = CopyPreview.of(
        signal: signal,
        account: account(equity: 1000000), // 1% = $10k / $750 = 13.33 lots
        riskPct: 1,
      );
      expect(p.refusal, CopyRefusal.maxLots);
      // The refused size is reported, so the sheet can say WHY — the same
      // contract as the server's refusal payload.
      expect(p.lots, 13.33);
    });

    test('zero equity cannot be sized', () {
      final CopyPreview p = CopyPreview.of(
        signal: signal,
        account: account(equity: 0),
        riskPct: 1,
      );
      expect(p.refusal, CopyRefusal.invalidSignal);
      expect(p.lots, 0);
      expect(p.maxLoss, 0);
    });

    test('the slider band is exactly the server clamp band', () {
      // A risk % the sheet can produce must survive clampRiskPct unchanged —
      // otherwise the preview and the placed order could disagree on size.
      for (final double r in <double>[0.25, 1.0, 2.5, 5.0]) {
        expect(CopySettings.clampRiskPct(r), r);
      }
    });
  });
}
