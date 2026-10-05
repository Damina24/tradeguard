import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/trade.dart';
import 'package:tradeguard/features/journal/domain/trade_grade.dart';
import 'package:tradeguard/features/journal/domain/trade_metrics.dart';
import 'package:tradeguard/features/journal/domain/trade_review.dart';

/// A complete trade: planned risk, planned reward, a 1R stop, and a configurable result.
Trade trade({
  String id = 't1',
  String accountId = 'acc-1',
  String symbol = 'EURUSD',
  TradeDirection direction = TradeDirection.long,
  double lots = 1,
  double pnl = 200,
  double? entry = 1.1000,
  double? exit = 1.1200,
  double? stop = 1.0900,
  double? target = 1.1200,
  double commission = 0,
  double swap = 0,
  DateTime? openTime,
  DateTime? closeTime,
  String? grade,
  bool sparse = false,
}) =>
    Trade(
      id: id,
      accountId: accountId,
      symbol: symbol,
      direction: direction,
      lots: lots,
      pnl: pnl,
      entry: entry,
      exit: exit,
      stop: stop,
      target: target,
      commission: commission,
      swap: swap,
      // `sparse` models an export that carried almost nothing, so every optional field is
      // genuinely null rather than defaulted.
      openTime: sparse ? null : (openTime ?? DateTime.utc(2026, 4, 15, 8)),
      closeTime: sparse ? null : (closeTime ?? DateTime.utc(2026, 4, 15, 12)),
      grade: grade,
    );

void main() {
  group('TradeGrade', () {
    test('uses exactly the product A-D vocabulary', () {
      expect(
        TradeGrade.values.map((TradeGrade g) => g.label),
        <String>['A', 'B', 'C', 'D'],
      );
    });

    test('parses the stored letter, case-insensitively', () {
      expect(TradeGrade.tryParse('A'), TradeGrade.a);
      expect(TradeGrade.tryParse('b'), TradeGrade.b);
      expect(TradeGrade.tryParse('  D  '), TradeGrade.d);
    });

    test('round-trips every grade', () {
      for (final TradeGrade g in TradeGrade.values) {
        expect(TradeGrade.tryParse(TradeGrade.encode(g)), g);
      }
    });

    test('refuses unknown or blank values rather than defaulting', () {
      // Defaulting an unknown grade would invent data the trader never entered.
      expect(TradeGrade.tryParse('Z'), isNull);
      expect(TradeGrade.tryParse(''), isNull);
      expect(TradeGrade.tryParse('  '), isNull);
      expect(TradeGrade.tryParse(null), isNull);
      expect(TradeGrade.encode(null), isNull);
    });

    test('orders quality A best to D worst', () {
      expect(TradeGrade.a.rank, lessThan(TradeGrade.d.rank));
    });
  });

  group('TradeMetrics', () {
    test('reproduces the persisted net P&L, never recomputing it', () {
      final Trade t = trade(pnl: 307.80, commission: -3.5, swap: -0.7);
      // The authoritative number is `pnl` as stored; costs are already netted off.
      expect(TradeMetrics.of(t).netPnl, 307.80);
    });

    test('computes R multiple from the stop-defined risk', () {
      // 100 pips risk on 1 lot is $1000, so +200 is +0.2R.
      final TradeMetrics m = TradeMetrics.of(trade(pnl: 200));
      expect(m.rMultiple, isNotNull);
      expect(m.rMultiple, closeTo(0.2, 0.0001));
    });

    test('R multiple is null when the export carried no stop', () {
      expect(TradeMetrics.of(trade(stop: null)).rMultiple, isNull);
    });

    test('R multiple is null when the stop sits on entry', () {
      // A degenerate export must not read as an infinite R win.
      expect(TradeMetrics.of(trade(stop: 1.1000)).rMultiple, isNull);
    });

    test('classifies outcome from the persisted value', () {
      expect(TradeMetrics.of(trade(pnl: 10)).isWin, isTrue);
      expect(TradeMetrics.of(trade(pnl: -10)).isWin, isFalse);
      expect(TradeMetrics.of(trade(pnl: 0)).isBreakeven, isTrue);
      expect(TradeMetrics.of(trade(pnl: 0)).isWin, isFalse);
    });

    test('flags a loss beyond 1R', () {
      expect(TradeMetrics.of(trade(pnl: -2000)).isBigLoss, isTrue);
      expect(TradeMetrics.of(trade(pnl: -50)).isBigLoss, isFalse);
    });

    test('pips and duration are null when timestamps or prices are missing', () {
      final TradeMetrics m = TradeMetrics.of(
        trade(entry: null, exit: null, sparse: true),
      );
      expect(m.pipsMoved, isNull);
      expect(m.heldFor, isNull);
    });

    test('a negative duration from a restated timestamp is clamped', () {
      final TradeMetrics m = TradeMetrics.of(
        trade(
          openTime: DateTime.utc(2026, 4, 15, 12),
          closeTime: DateTime.utc(2026, 4, 15, 8),
        ),
      );
      expect(m.heldFor, Duration.zero);
    });

    test('costs sum the persisted columns', () {
      expect(
        TradeMetrics.of(trade(commission: -3.5, swap: -0.7)).costs,
        closeTo(-4.2, 0.0001),
      );
    });

    test('is a pure function of the trade', () {
      final Trade t = trade();
      expect(TradeMetrics.of(t).netPnl, TradeMetrics.of(t).netPnl);
      expect(TradeMetrics.of(t).rMultiple, TradeMetrics.of(t).rMultiple);
    });
  });

  group('gross P&L', () {
    test('is the persisted net plus back out the persisted costs', () {
      // pnl is net, so gross = pnl - (commission + swap).
      final Trade t = trade(pnl: 307.80, commission: -3.5, swap: -0.7);
      expect(t.grossPnl, closeTo(312.00, 0.0001));
    });

    test('equals pnl when there are no costs', () {
      expect(trade(pnl: 100).grossPnl, 100);
    });
  });
group('TradeReview grading boundaries', () {
    test('a planned, winning, high-R trade grades A', () {
      // Risk is 100 pips on 1 lot = $1000, so +1000 is exactly 1R with the plan intact.
      final TradeReview r = TradeReview.of(
        TradeMetrics.of(trade(pnl: 1000, commission: -1, swap: -1)),
      );
      expect(r.grade, TradeGrade.a);
      expect(r.compliance, greaterThanOrEqualTo(0.8));
    });

    test('a winning trade under 1R cannot grade A', () {
      final TradeReview r = TradeReview.of(
        TradeMetrics.of(trade(pnl: 50, commission: -1, swap: -1)),
      );
      expect(r.grade, isNot(TradeGrade.a));
    });

    test('exactly at 1R still counts as a met target', () {
      final TradeReview r = TradeReview.of(TradeMetrics.of(trade(pnl: 1000)));
      expect(
        r.reasons.any((ReviewReason x) => x.evidence == '+1.00R'),
        isTrue,
      );
    });

    test('a win with no stop cannot earn an A (risk was undefined)', () {
      final TradeReview r = TradeReview.of(
        TradeMetrics.of(trade(stop: null, pnl: 500)),
      );
      expect(r.grade, isNot(TradeGrade.a));
      expect(r.metrics.rMultiple, isNull);
    });

    test('a losing trade that respected its stop is not a D', () {
      // Process intact, outcome bad — that is the definition of a good loser.
      final TradeReview r = TradeReview.of(TradeMetrics.of(trade(pnl: -50)));
      expect(r.grade, isNot(TradeGrade.d));
      expect(r.grade, anyOf(TradeGrade.b, TradeGrade.c));
    });

    test('a losing trade that broke its stop and had no plan is a D', () {
      final TradeReview r = TradeReview.of(
        TradeMetrics.of(trade(pnl: -5000, stop: null, target: null)),
      );
      expect(r.grade, TradeGrade.d);
    });

    test('a fully planned winner grades at least B', () {
      final TradeReview r = TradeReview.of(TradeMetrics.of(trade(pnl: 200)));
      expect(
        r.grade,
        anyOf(TradeGrade.a, TradeGrade.b),
        reason: 'plan intact + win must not fall below B',
      );
    });

    test('break-even is neither a win nor a loss claim', () {
      final TradeReview r = TradeReview.of(TradeMetrics.of(trade(pnl: 0)));
      expect(
        r.reasons.any((ReviewReason x) => x.text.contains('break-even')),
        isTrue,
      );
    });

    test('a trade with no plan at all still produces a grade and reasons', () {
      final TradeReview r = TradeReview.of(
        TradeMetrics.of(trade(stop: null, target: null, pnl: 10)),
      );
      expect(r.grade, isNotNull);
      expect(r.reasons, isNotEmpty);
      expect(r.totalCount, greaterThan(0));
    });

    test('costs that exceed a tiny win are flagged', () {
      final TradeReview r = TradeReview.of(
        TradeMetrics.of(trade(pnl: 1, commission: -50, swap: -50)),
      );
      expect(
        r.reasons.any(
          (ReviewReason x) => !x.passed && x.text.contains('wiped out'),
        ),
        isTrue,
      );
    });

    test('is deterministic — the same trade always grades the same', () {
      final Trade t = trade(pnl: 123.45, commission: -2, swap: -1);
      final TradeReview a = TradeReview.of(TradeMetrics.of(t));
      final TradeReview b = TradeReview.of(TradeMetrics.of(t));
      expect(a.grade, b.grade);
      expect(a.passedCount, b.passedCount);
      expect(
        a.reasons.map((ReviewReason r) => r.text),
        b.reasons.map((ReviewReason r) => r.text),
      );
    });

    test('every grade produced stays inside the A-D vocabulary', () {
      for (final double pnl in <double>[1000, 100, 0, -50, -5000]) {
        for (final bool planned in <bool>[true, false]) {
          final TradeReview r = TradeReview.of(
            TradeMetrics.of(
              trade(
                pnl: pnl,
                stop: planned ? 1.0900 : null,
                target: planned ? 1.1200 : null,
              ),
            ),
          );
          expect(TradeGrade.values, contains(r.grade));
        }
      }
    });
  });

  group('TradeReview explanations', () {
    test('explains a missing stop loss', () {
      final TradeReview r =
          TradeReview.of(TradeMetrics.of(trade(stop: null)));
      expect(
        r.reasons.any((ReviewReason x) => !x.passed && x.text.contains('stop')),
        isTrue,
      );
    });

    test('reports the win in words', () {
      final TradeReview r = TradeReview.of(TradeMetrics.of(trade(pnl: 200)));
      expect(
        r.reasons.any((ReviewReason x) => x.text.contains('profit')),
        isTrue,
      );
    });

    test('every reason has trader-safe, non-empty text', () {
      final TradeReview r = TradeReview.of(TradeMetrics.of(trade()));
      for (final ReviewReason x in r.reasons) {
        expect(x.text.trim(), isNotEmpty);
        expect(x.text, isNot(contains('Exception')));
        expect(x.text, isNot(contains('null')));
      }
    });

    test('counts for the compliance bar add up', () {
      final TradeReview r = TradeReview.of(TradeMetrics.of(trade()));
      expect(r.passedCount, lessThanOrEqualTo(r.totalCount));
      expect(r.compliance, inInclusiveRange(0, 1));
    });

    test('headline carries the R and the letter', () {
      final TradeReview r = TradeReview.of(TradeMetrics.of(trade(pnl: 200)));
      expect(r.headline, contains('R'));
      expect(r.headline, contains(r.grade.label));
    });
  });
}