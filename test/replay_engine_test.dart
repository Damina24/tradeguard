import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/trade.dart';
import 'package:tradeguard/features/replay/domain/price_bar.dart';
import 'package:tradeguard/features/replay/domain/replay_engine.dart';
import 'package:tradeguard/features/replay/domain/replay_result.dart';
import 'package:tradeguard/features/replay/domain/replay_scan.dart';
import 'package:tradeguard/features/replay/domain/replay_setup.dart';

/// One bar. Defaults are flat around 100, so a test only has to state what it means to assert.
///
/// Wicks always sit outside the body, so a hand-written fixture is well-formed unless a test
/// deliberately makes it otherwise.
PriceBar bar({
  int minutes = 0,
  double? open,
  double? high,
  double? low,
  double? close,
}) {
  final double o = open ?? 100;
  final double c = close ?? o;
  return PriceBar(
    time: DateTime.utc(2024, 1, 2).add(Duration(minutes: minutes)),
    open: o,
    high: high ?? (o > c ? o : c) + 1,
    low: low ?? (o < c ? o : c) - 1,
    close: c,
  );
}

/// A long from 100 with a 5-point stop and a 10-point target: exactly 1R / 2R.
const ReplaySetup longSetup = ReplaySetup(
  symbol: 'XAUUSD',
  direction: TradeDirection.long,
  entry: 100,
  stop: 95,
  target: 110,
);

const ReplaySetup shortSetup = ReplaySetup(
  symbol: 'XAUUSD',
  direction: TradeDirection.short,
  entry: 100,
  stop: 105,
  target: 90,
);

const ReplayEngine engine = ReplayEngine();

/// A steady uptrend with tight, explicit wicks, so the stop is never accidentally touched.
///
/// Note the helper defaults: `bar()` adds a one-unit wick above and below the body, which is right for
/// a fixture that does not care but wrong here — a level test that means to stay clear of the stop must
/// state its own high and low, or the default wick silently reaches it and the test passes for the
/// wrong reason.
PriceBar cleanBar({
  required int minutes,
  required double close,
  double? high,
  double? low,
  double? open,
}) {
  final double o = open ?? close;
  return PriceBar(
    time: DateTime.utc(2024, 1, 2).add(Duration(minutes: minutes)),
    open: o,
    high: high ?? (o > close ? o : close) + 0.25,
    low: low ?? (o < close ? o : close) - 0.25,
    close: close,
  );
}

void main() {
  group('validation is total, not partial', () {
    test('an invalid setup is reported, not silently scored', () {
      // A long whose stop sits ABOVE the entry has no R. Scoring it anyway would produce a number the
      // trader could not interpret.
      const ReplaySetup inverted = ReplaySetup(
        symbol: 'XAUUSD',
        direction: TradeDirection.long,
        entry: 100,
        stop: 105,
      );
      expect(inverted.isValid, isFalse);
      expect(inverted.validationError, contains('BELOW'));

      final ReplayResult r = engine.run(<PriceBar>[bar(), bar(minutes: 1)], inverted);
      expect(r.status, ReplayStatus.invalid);
      expect(r.rMultiple, isNull);
    });

    test('an empty series never fills', () {
      expect(
        engine.run(const <PriceBar>[], longSetup).status,
        ReplayStatus.notFilled,
      );
    });

    test('a one-bar series fills but cannot exit on its own bar', () {
      // Rule 2: the entry bar cannot also be the exit bar, so a single bar yields an OPEN position.
      final ReplayResult r = engine.run(<PriceBar>[bar()], longSetup);
      expect(r.status, ReplayStatus.unresolved);
      expect(r.didFill, isTrue);
    });
  });

  group('fills', () {
    test('the first bar trading through the entry is the fill', () {
      final ReplayResult r = engine.run(
        <PriceBar>[bar(), bar(minutes: 1), bar(minutes: 2)],
        longSetup,
      );
      expect(r.fillIndex, 0);
      expect(r.fillPrice, 100);
    });

    test('price that never reaches the entry never fills', () {
      // `cleanBar` rather than `bar`: `bar()` defaults open to 100, so `bar(close: 90)` still produced a
      // range of [89, 101] — which CONTAINS the entry, and would fill. The fixture has to state its own
      // open or the test passes for entirely the wrong reason.
      final ReplayResult r = engine.run(
        <PriceBar>[
          cleanBar(minutes: 0, close: 90),
          cleanBar(minutes: 1, close: 89),
        ],
        longSetup,
      );
      expect(r.status, ReplayStatus.notFilled);
      expect(r.didFill, isFalse);
      expect(r.rMultiple, isNull, reason: 'an untriggered setup has no result to report');
      expect(r.countsAsTrade, isFalse);
    });

    test('a gap through the entry fills at the open, not the requested price', () {
      // Rule 1. A gap only exists if the bar still TRADES THROUGH the entry — otherwise nothing filled at
      // all and "it gapped" is a claim about a trade that never happened.

      // (a) The range contains 100 and the bar opens at 100: fills at the level.
      final ReplayResult atLevel = engine.run(
        <PriceBar>[cleanBar(minutes: 0, close: 100, open: 100, high: 101, low: 99)],
        longSetup,
      );
      expect(atLevel.didFill, isTrue);
      expect(atLevel.fillPrice, 100);

      // (b) The range still reaches 100, but the bar OPENED at 103. The only price that existed at the
      // open was 103, so that is the fill — filling at 100 would report a profit nobody could have got.
      final ReplayResult gapUp = engine.run(
        <PriceBar>[
          cleanBar(minutes: 0, close: 104, open: 103, high: 105, low: 99),
        ],
        longSetup,
      );
      expect(gapUp.didFill, isTrue);
      expect(gapUp.fillPrice, 103);

      // (c) The range never reaches the entry at all, so nothing trades.
      final ReplayResult never = engine.run(
        <PriceBar>[
          cleanBar(minutes: 0, close: 104, open: 103, high: 105, low: 102),
        ],
        longSetup,
      );
      expect(never.status, ReplayStatus.notFilled);
    });
  });

  group('exits', () {
    test('the target is taken at the target price', () {
      // The wicks are stated explicitly: the default ±1 would reach the 95 stop on bar 1 and the trade
      // would stop out before it ever reached the target.
      final ReplayResult r = engine.run(
        <PriceBar>[
          cleanBar(minutes: 0, close: 100),
          cleanBar(minutes: 1, close: 109, high: 111, low: 108),
        ],
        longSetup,
      );
      expect(r.status, ReplayStatus.targetHit);
      expect(r.exitPrice, 110);
      expect(r.rMultiple, 2.0, reason: 'a 10-point move on a 5-point stop is exactly 2R');
      expect(r.isWin, isTrue);
      expect(r.barsHeld, 1);
    });

    test('the stop is taken at the stop price', () {
      final ReplayResult r = engine.run(
        <PriceBar>[
          cleanBar(minutes: 0, close: 100),
          cleanBar(minutes: 1, close: 96, high: 97, low: 94),
        ],
        longSetup,
      );
      expect(r.status, ReplayStatus.stopHit);
      expect(r.exitPrice, 95);
      expect(r.rMultiple, -1.0);
      expect(r.isLoss, isTrue);
    });

    test('a short profits when price falls', () {
      final ReplayResult r = engine.run(
        <PriceBar>[
          cleanBar(minutes: 0, close: 100),
          cleanBar(minutes: 1, close: 91, high: 92, low: 89),
        ],
        shortSetup,
      );
      expect(r.status, ReplayStatus.targetHit);
      expect(r.rMultiple, 2.0);
    });

    test('a gap THROUGH the stop fills at the open', () {
      final ReplayResult r = engine.run(
        <PriceBar>[
          bar(),
          bar(minutes: 1, open: 90, high: 92, low: 88, close: 91),
        ],
        longSetup,
      );
      expect(r.status, ReplayStatus.stopHit);
      expect(r.exitPrice, 90, reason: 'the open was the only price that existed');
      expect(r.rMultiple, lessThan(-1.0));
    });
  });

  group('the pessimistic tie-break: same-bar stop AND target is a loss', () {
    // The single most consequential rule in the engine. OHLC does not record intrabar order, so the
    // sequence is unknowable and must resolve to the worse outcome. Resolving it optimistically is the
    // classic way a losing system gets reported as a winning one.
    test('a long spanning both levels on one bar is a stop', () {
      final ReplayResult r = engine.run(
        <PriceBar>[
          cleanBar(minutes: 0, close: 100),
          cleanBar(minutes: 1, open: 100, close: 108, high: 115, low: 90),
        ],
        longSetup,
      );
      expect(r.status, ReplayStatus.stopHit);
      expect(r.isWin, isFalse);
    });

    test('a short spanning both levels on one bar is a stop', () {
      final ReplayResult r = engine.run(
        <PriceBar>[
          cleanBar(minutes: 0, close: 100),
          cleanBar(minutes: 1, open: 100, close: 92, high: 110, low: 85),
        ],
        shortSetup,
      );
      expect(r.status, ReplayStatus.stopHit);
      expect(r.isWin, isFalse);
    });
  });

  group('unresolved positions', () {
    test('a trade that never resolves is marked, not closed', () {
      // Rule 4. Closing it at the last close and calling it a RESULT would be inventing an exit.
      final ReplayResult r = engine.run(
        <PriceBar>[
          cleanBar(minutes: 0, close: 100),
          cleanBar(minutes: 1, close: 102),
          cleanBar(minutes: 2, close: 103),
        ],
        longSetup,
      );
      expect(r.status, ReplayStatus.unresolved);
      expect(r.isResolved, isFalse);
      expect(r.exitPrice, 103);
      expect(r.rMultiple, 0.6, reason: '3 points on a 5-point stop');
      expect(r.countsAsTrade, isTrue, reason: 'the position existed and held risk');
      expect(r.isWin, isFalse, reason: 'still open is not a win');
    });
  });

  group('excursions', () {
    test('MFE and MAE are measured in R from the fill', () {
      final ReplayResult r = engine.run(
        <PriceBar>[
          cleanBar(minutes: 0, close: 100),
          cleanBar(minutes: 1, close: 108), // +8 points
          cleanBar(minutes: 2, close: 96), // -4 points
          cleanBar(minutes: 3, close: 112, high: 113), // through the 110 target
        ],
        longSetup,
      );
      expect(r.status, ReplayStatus.targetHit);
      expect(r.mfeR, 1.6, reason: '8 points on a 5-point stop');
      expect(r.maeR, -0.8, reason: '4 points against');
    });

    test('a null excursion is possible when the stop cannot be priced', () {
      // Never reached through `run` (an invalid setup returns early), but the accessors must not throw
      // for a hand-built result.
      const ReplayResult bare = ReplayResult(
        setup: ReplaySetup(
          symbol: 'XAUUSD',
          direction: TradeDirection.long,
          entry: 0,
          stop: 0,
        ),
        status: ReplayStatus.notFilled,
      );
      expect(bare.mfeR, isNull);
      expect(bare.maeR, isNull);
      expect(bare.pnl, isNull);
    });
  });

  group('determinism', () {
    test('the same input always produces the same result', () {
      // A backtest that answers differently each time it is opened is worse than no backtest, because
      // the trader cannot check it.
      final List<PriceBar> bars = <PriceBar>[
        for (int i = 0; i < 40; i++)
          bar(
            minutes: i,
            close: 100 + (i % 7) - (i % 11) / 2,
            high: 100 + (i % 7) + 1,
            low: 100 - (i % 11) / 2 - 1,
          ),
      ];
      final ReplayResult first = engine.run(bars, longSetup);
      for (int i = 0; i < 5; i++) {
        final ReplayResult again = engine.run(bars, longSetup);
        expect(again.status, first.status);
        expect(again.exitIndex, first.exitIndex);
        expect(again.rMultiple, first.rMultiple);
      }
    });
  });

  group('the scan never inflates its own sample', () {
    /// A steady uptrend, so setups trigger repeatedly and the reporting floor is reachable.
    ///
    /// Wicks are deliberately TIGHT (±0.25). `bar()`'s default ±1 wick would reach the 5-point stop on
    /// the very next bar of a 0.5-per-bar uptrend, so every scan would resolve as an instant loss and the
    /// fixture would silently test the wrong thing.
    final List<PriceBar> rising = <PriceBar>[
      for (int i = 0; i < 30; i++)
        cleanBar(minutes: i, close: 100 + i * 0.5),
    ];

    test('a scan reports its own sample size and floor', () {
      final ReplayScan scan = ReplayScan.run(bars: rising, setup: longSetup);
      expect(scan.attempts, 30);
      expect(
        scan.sampleTrades + scan.unfilled.length,
        30,
        reason: 'every attempt either traded or never triggered',
      );
      expect(scan.minimumTrades, 10);
    });

    test('below the floor nothing may be reported as a finding', () {
      final ReplayScan scan = ReplayScan.run(
        bars: rising,
        setup: longSetup,
        thresholds: const ReplayScanThresholds(minTrades: 1000),
      );
      expect(scan.isInsufficientData, isTrue);
    });

    test('an unfilled setup is not counted as a trade, and not as a loss', () {
      // The most flattering error available: treating "never triggered" as a loss makes a selective
      // entry look like it missed money.
      //
      // Asserted on the ENGINE, because a scan re-anchors the entry onto each bar's close — so any entry
      // near the price is reached immediately and the unfilled path cannot be provoked from a scan.
      const ReplaySetup unreachable = ReplaySetup(
        symbol: 'XAUUSD',
        direction: TradeDirection.long,
        entry: 5000,
        stop: 4990,
      );
      final ReplayResult single = engine.run(rising, unreachable);
      expect(single.status, ReplayStatus.notFilled);
      expect(single.countsAsTrade, isFalse);
      expect(single.isWin, isFalse);
      expect(single.isLoss, isFalse);
      expect(single.rMultiple, isNull);
    });

    test('an invalid setup produces no attempts at all', () {
      const ReplaySetup inverted = ReplaySetup(
        symbol: 'XAUUSD',
        direction: TradeDirection.long,
        entry: 100,
        stop: 105,
      );
      final ReplayScan scan = ReplayScan.run(bars: rising, setup: inverted);
      expect(scan.attempts, 0);
      expect(scan.sampleTrades, 0);
      expect(scan.winRatePct, isNull);
    });

    test('a flawless run has no profit factor rather than an infinite one', () {
      // "∞" beside a backtest invites the reader to treat it as a measured edge.
      final List<PriceBar> winners = <PriceBar>[
        for (int i = 0; i < 20; i += 2)
          bar(minutes: i, close: 100, high: 101, low: 99),
        for (int i = 1; i < 20; i += 2)
          bar(minutes: i, close: 113, high: 115, low: 112),
      ];
      final ReplayScan scan = ReplayScan.run(bars: winners, setup: longSetup);
      expect(scan.losses, 0);
      expect(scan.profitFactorR, isNull);
      expect(scan.isInsufficientData, isFalse);
    });

    test('the scan and a one-shot replay agree about the same bar', () {
      // Two implementations of the fill rules would eventually disagree, and the screen would then show
      // a rate its own detail card contradicts.
      const ReplaySetup anchored = ReplaySetup(
        symbol: 'XAUUSD',
        direction: TradeDirection.long,
        entry: 100,
        stop: 98,
        target: 104,
      );
      final ReplaySetup reanchored = ReplayScan.reanchor(anchored, rising[5]);
      expect(reanchored.entry, rising[5].close);
      expect(reanchored.stop, reanchored.entry - anchored.riskDistance);
      expect(reanchored.rewardRisk, anchored.rewardRisk);

      final ReplayResult single = engine.run(rising, reanchored);
      final ReplayResult inScan = ReplayScan.run(bars: rising, setup: anchored).results[5];
      expect(inScan.status, single.status);
      expect(inScan.rMultiple, single.rMultiple);
    });

    test('an empty series yields an empty scan rather than throwing', () {
      final ReplayScan scan =
          ReplayScan.run(bars: const <PriceBar>[], setup: longSetup);
      expect(scan.attempts, 0);
      expect(scan.sampleTrades, 0);
      expect(scan.winRatePct, isNull);
      expect(scan.totalR, isNull);
    });
  });

  group('hostile input', () {
    test('a very large move does not overflow the R calculation', () {
      final ReplayResult r = engine.run(
        <PriceBar>[
          bar(),
          bar(minutes: 1, high: 1e6, low: 1e5, close: 1e6),
        ],
        longSetup,
      );
      expect(r.status, ReplayStatus.targetHit);
      expect(r.rMultiple!.isFinite, isTrue);
    });

    test('a hand-built reversed series does not crash the engine', () {
      // Order is the CALLER's contract — `PriceBar.fromCacheList` sorts. The engine must not crash on a
      // list built by hand in the wrong order; it simply reports what that list implies.
      final List<PriceBar> reversed = <PriceBar>[bar(minutes: 2), bar(minutes: 1), bar()];
      expect(engine.run(reversed, longSetup).status, isNot(ReplayStatus.invalid));
    });
  });
}