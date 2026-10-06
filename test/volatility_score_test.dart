import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/features/replay/domain/price_bar.dart';
import 'package:tradeguard/features/signals/domain/volatility_score.dart';

/// One well-formed bar: an open == close == previous close doji at [price]
/// with an upper wick of [range]. Because every close is the same price,
/// the true range of bar i is exactly [range] — which lets each fixture
/// below state the number it expects without re-deriving the formula under
/// test.
PriceBar bar(int index, double range, {double price = 100}) => PriceBar(
      time: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
      open: price,
      high: price + range,
      low: price,
      close: price,
    );

/// Every bar ranges identically — the neutral reading.
List<PriceBar> constantBars(int n, {double range = 2}) =>
    <PriceBar>[for (int i = 0; i < n; i++) bar(i, range)];

/// True range grows by one per bar: a market that just got loud.
List<PriceBar> rampBars(int n) =>
    <PriceBar>[for (int i = 0; i < n; i++) bar(i, i.toDouble())];

/// True range shrinks by one per bar: a market settling down.
List<PriceBar> reverseRampBars(int n) =>
    <PriceBar>[for (int i = 0; i < n; i++) bar(i, (n - i).toDouble())];

/// Exactly the boundary fixture: 14 baseline true ranges of 1 followed by
/// 14 recent true ranges of 2 — a textbook doubling.
List<PriceBar> stepBars(int n) => <PriceBar>[
      for (int i = 0; i < n; i++) bar(i, i <= 14 ? 1.0 : 2.0),
    ];

/// No movement at all: every true range is zero.
List<PriceBar> flatBars(int n) => constantBars(n, range: 0);

/// Fourteen zero true ranges, then fourteen true ranges of 1 — the
/// "was flat, now moving" case the zero-baseline guard exists for.
List<PriceBar> zeroThenMoveBars(int n) => <PriceBar>[
      for (int i = 0; i < n; i++) bar(i, i <= 14 ? 0.0 : 1.0),
    ];

void main() {
  group('VolatilityBand', () {
    test('floors split the 0…100 range into four exclusive bands', () {
      expect(VolatilityBand.forScore(0), VolatilityBand.calm);
      expect(VolatilityBand.forScore(39), VolatilityBand.calm);
      expect(VolatilityBand.forScore(40), VolatilityBand.moderate);
      expect(VolatilityBand.forScore(59), VolatilityBand.moderate);
      expect(VolatilityBand.forScore(60), VolatilityBand.elevated);
      expect(VolatilityBand.forScore(79), VolatilityBand.elevated);
      expect(VolatilityBand.forScore(80), VolatilityBand.high);
      expect(VolatilityBand.forScore(100), VolatilityBand.high);
    });

    test('out-of-range scores clamp instead of crashing a screen', () {
      expect(VolatilityBand.forScore(-5), VolatilityBand.calm);
      expect(VolatilityBand.forScore(999), VolatilityBand.high);
    });

    test('every band has a distinct label for the radar to print', () {
      final List<String> labels =
          VolatilityBand.values.map((VolatilityBand b) => b.label).toList();
      expect(labels.toSet(), hasLength(VolatilityBand.values.length));
      expect(labels.every((String l) => l.isNotEmpty), isTrue);
    });
  });

  group('VolatilityScore.of — floors', () {
    test('an empty series yields null, not a score', () {
      expect(VolatilityScore.of(const <PriceBar>[]), isNull);
    });

    test('one bar below the window floor yields null', () {
      expect(VolatilityScore.of(rampBars(VolatilityScore.minBars - 1)), isNull);
    });

    test('exactly minBars is the first measurable series', () {
      final VolatilityScore? score =
          VolatilityScore.of(rampBars(VolatilityScore.minBars));
      expect(score, isNotNull);
      expect(score!.barCount, VolatilityScore.minBars);
    });

    test('malformed bars are dropped, not counted and not fatal', () {
      final List<PriceBar> clean = constantBars(29);
      final PriceBar badShape = PriceBar(
        time: clean.last.time.add(const Duration(hours: 1)),
        open: 100,
        high: 90, // high below the body — refused by isWellFormed
        low: 110,
        close: 100,
      );
      final PriceBar badPrice = PriceBar(
        time: clean.last.time.add(const Duration(hours: 2)),
        open: double.nan,
        high: 101,
        low: 99,
        close: 100,
      );
      final VolatilityScore? withBad = VolatilityScore.of(
        <PriceBar>[...clean, badShape, badPrice],
      );
      final VolatilityScore? without = VolatilityScore.of(clean);
      expect(withBad, isNotNull);
      expect(withBad!.barCount, without!.barCount);
      expect(withBad.score, without.score);
      expect(withBad.rangePct, without.rangePct);
    });

    test('a series that becomes too short after dropping still yields null',
        () {
      // 29 bars of which two are malformed → 27 usable, below the floor.
      final List<PriceBar> bars = constantBars(27);
      final PriceBar bad = PriceBar(
        time: bars.last.time.add(const Duration(hours: 1)),
        open: 100,
        high: 90,
        low: 110,
        close: 100,
      );
      expect(
        VolatilityScore.of(<PriceBar>[...bars, bad, bad]),
        isNull,
      );
    });
  });

  group('VolatilityScore.of — hand-computable fixtures', () {
    test('a constant-range series scores the neutral 50 exactly', () {
      final VolatilityScore? score = VolatilityScore.of(constantBars(40));
      expect(score, isNotNull);
      // Both windows contain the same true range, so expansion is 1.0 →
      // component 50, and min == max makes the position component 50 too.
      expect(score!.score, 50);
      expect(score.band, VolatilityBand.moderate);
      expect(score.baselineAtr, 2.0);
      expect(score.recentAtr, 2.0);
      expect(score.rangePct, closeTo(2.0, 1e-9)); // 2 price units on 100
      expect(score.expansionPct, closeTo(0.0, 1e-9));
    });

    test('a doubling of range scores the maximum and says so', () {
      final VolatilityScore? score = VolatilityScore.of(stepBars(29));
      expect(score, isNotNull);
      // baseline ATR 1, recent ATR 2: expansion component 100 (log2 doubling
      // around the neutral 50), position component 100 (recent == max).
      expect(score!.score, 100);
      expect(score.band, VolatilityBand.high);
      expect(score.baselineAtr, 1.0);
      expect(score.recentAtr, 2.0);
      expect(score.expansionPct, closeTo(100.0, 1e-9));
      expect(score.rangePct, closeTo(2.0, 1e-9));
    });

    test('an exploding series lands in the high band', () {
      final VolatilityScore? score = VolatilityScore.of(rampBars(40));
      expect(score, isNotNull);
      expect(score!.score, inInclusiveRange(85, 95));
      expect(score.band, VolatilityBand.high);
      expect(score.expansionPct, greaterThan(100));
    });

    test('a collapsing series lands in the calm band', () {
      final VolatilityScore? score = VolatilityScore.of(reverseRampBars(40));
      expect(score, isNotNull);
      expect(score!.score, inInclusiveRange(5, 15));
      expect(score.band, VolatilityBand.calm);
      expect(score.expansionPct, lessThan(0));
    });
  });

  group('VolatilityScore.of — guards', () {
    test('an all-flat series is neutral, never NaN', () {
      final VolatilityScore? score = VolatilityScore.of(flatBars(40));
      expect(score, isNotNull);
      // Every true range is zero: 0/0 reads as "no change" (neutral 50),
      // and the uniform-series rule makes the position component 50.
      expect(score!.score, 50);
      expect(score.band, VolatilityBand.moderate);
      expect(score.rangePct, 0);
      expect(score.expansionPct, 0);
      expect(score.rangePct.isFinite, isTrue);
      expect(score.expansionPct.isFinite, isTrue);
    });

    test('flat then moving reads as maximal expansion, still finite', () {
      final VolatilityScore? score = VolatilityScore.of(zeroThenMoveBars(40));
      expect(score, isNotNull);
      // Zero baseline with movement: the ratio clamps to maxRatio, so the
      // expansion component pins at 100 instead of dividing by zero.
      expect(score!.score, 100);
      expect(score.band, VolatilityBand.high);
      expect(score.expansionPct, closeTo(300.0, 1e-9)); // (4.0 − 1) × 100
      expect(score.rangePct.isFinite, isTrue);
      expect(score.baselineAtr, 0);
    });

    test('every produced number is finite and the score within 0…100', () {
      final List<PriceBar> spiky = <PriceBar>[
        for (int i = 0; i < 60; i++) bar(i, i.isEven ? 0.1 : 50.0),
      ];
      final VolatilityScore? score = VolatilityScore.of(spiky);
      expect(score, isNotNull);
      expect(score!.score, inInclusiveRange(0, 100));
      expect(score.rangePct.isFinite, isTrue);
      expect(score.expansionPct.isFinite, isTrue);
      expect(score.baselineAtr.isFinite, isTrue);
      expect(score.recentAtr.isFinite, isTrue);
    });
  });

  group('VolatilityScore.of — determinism', () {
    test('the same bars always produce the same reading', () {
      final List<PriceBar> bars = rampBars(40);
      final VolatilityScore? a = VolatilityScore.of(bars);
      final VolatilityScore? b = VolatilityScore.of(bars);
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a!.score, b!.score);
      expect(a.baselineAtr, b.baselineAtr);
      expect(a.recentAtr, b.recentAtr);
      expect(a.rangePct, b.rangePct);
      expect(a.expansionPct, b.expansionPct);
    });

    test('input order does not flip the recent/baseline comparison', () {
      final List<PriceBar> ascending = rampBars(40);
      final List<PriceBar> descending = ascending.reversed.toList();
      final VolatilityScore? a = VolatilityScore.of(ascending);
      final VolatilityScore? b = VolatilityScore.of(descending);
      expect(a!.score, b!.score);
      expect(a.expansionPct, b.expansionPct);
    });

    test('the caller\'s list is never mutated', () {
      final List<PriceBar> descending = rampBars(40).reversed.toList();
      final DateTime first = descending.first.time;
      final DateTime last = descending.last.time;
      VolatilityScore.of(descending);
      expect(descending.first.time, first);
      expect(descending.last.time, last);
      expect(first.isAfter(last), isTrue); // still newest-first
    });
  });
}
