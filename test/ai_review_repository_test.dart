import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/ai_review.dart';
import 'package:tradeguard/core/models/trade.dart';
import 'package:tradeguard/features/ai_review/data/ai_review_repository.dart';
import 'package:tradeguard/features/ai_review/data/mock_ai_review_repository.dart';
import 'package:tradeguard/features/journal/domain/trade_metrics.dart';
import 'package:tradeguard/features/journal/domain/trade_review.dart';

/// A trade the mock can review.
Trade trade({
  String id = 't1',
  String symbol = 'XAUUSD',
  double pnl = 400,
  double? entry = 2345.0,
  double? exit = 2360.0,
  double? stop = 2338.0,
  double? target = 2365.0,
}) =>
    Trade(
      id: id,
      accountId: 'acc-1',
      symbol: symbol,
      direction: TradeDirection.long,
      lots: 0.5,
      pnl: pnl,
      entry: entry,
      exit: exit,
      stop: stop,
      target: target,
      closeTime: DateTime.utc(2026, 4, 15, 12),
    );

/// A repository that never answers, so the loading state can be held open.
class _PendingRepository implements AiReviewRepository {
  @override
  bool get isStubbed => false;

  @override
  Future<AiReview?> fetchReview(String tradeId) async =>
      Completer<AiReview?>().future;

  @override
  Future<AiReview> requestReview(String tradeId) async =>
      Completer<AiReview>().future;
}

/// The mock, wired to a one-trade journal.
MockAiReviewRepository mockOver(List<Trade> trades) {
  final MockAiReviewRepository repo =
      MockAiReviewRepository(latency: Duration.zero);
  repo.tradesLookup = (String id) {
    for (final Trade t in trades) {
      if (t.id == id) return t;
    }
    return null;
  };
  return repo;
}

void main() {
  group('MockAiReviewRepository — normal behaviour', () {
    test('produces a review for a known trade', () async {
      final AiReview review = await mockOver(<Trade>[trade()]).requestReview('t1');

      expect(review.summary, contains('XAUUSD'));
      expect(review.tradeId, 't1');
      expect(review.score, inInclusiveRange(0, 100));
    });

    test('is deterministic for the same trade', () async {
      final AiReview a = await mockOver(<Trade>[trade()]).requestReview('t1');
      final AiReview b = await mockOver(<Trade>[trade()]).requestReview('t1');

      expect(a.summary, b.summary);
      expect(a.leak, b.leak);
      expect(a.score, b.score);
      expect(a.suggestions, b.suggestions);
    });

    test('agrees with the deterministic checklist grade', () {
      // The mock must not become a second, contradictory opinion: both derive from TradeReview.
      final Trade t = trade();
      final TradeReview review = TradeReview.of(TradeMetrics.of(t));
      final AiReview ai = MockAiReviewRepository.buildFor(t);

      expect(ai.score, (review.compliance * 100).round());
    });

    test('caches a review so a repeat request is idempotent', () async {
      final MockAiReviewRepository repo = mockOver(<Trade>[trade()]);
      final AiReview first = await repo.requestReview('t1');
      final AiReview second = await repo.requestReview('t1');

      expect(second.summary, first.summary);
      expect(await repo.fetchReview('t1'), isNotNull);
    });

    test('reports itself as stubbed', () {
      expect(mockOver(<Trade>[trade()]).isStubbed, isTrue);
    });

    test('fetching an unreviewed trade is null, not an error', () async {
      // "Not reviewed yet" is the card's initial state and is a real, meaningful answer.
      expect(await mockOver(<Trade>[trade()]).fetchReview('t1'), isNull);
    });

    test('names the leak with real checklist evidence', () {
      // No stop recorded means the risk was undefined — a genuine, evidenced weakness.
      final AiReview review =
          MockAiReviewRepository.buildFor(trade(stop: null, target: null));
      expect(review.leak.toLowerCase(), contains('stop'));
      expect(review.suggestions, isNotEmpty);
    });

    test('reports no leak when every rule was met', () {
      final AiReview review = MockAiReviewRepository.buildFor(
        trade(pnl: 900, exit: 2366.0),
      );
      expect(review.leak, 'None identified.');
    });

    test('reports the R multiple when the stop allows it', () {
      expect(MockAiReviewRepository.buildFor(trade()).summary, contains('R'));
    });

    test('says so when the export carries no usable stop', () {
      final AiReview review =
          MockAiReviewRepository.buildFor(trade(stop: null, target: null));
      expect(review.summary.toLowerCase(), contains('no usable stop'));
    });
  });

  group('MockAiReviewRepository — account isolation', () {
    test('an unknown trade id is refused', () async {
      final MockAiReviewRepository repo = mockOver(<Trade>[trade()]);
      await expectLater(
        repo.requestReview('someone-elses-trade'),
        throwsA(
          isA<AiReviewException>().having(
            (AiReviewException e) => e.failure,
            'failure',
            AiReviewFailure.tradeUnavailable,
          ),
        ),
      );
    });

    test('a foreign trade id is refused identically', () async {
      final MockAiReviewRepository repo = mockOver(<Trade>[trade()]);
      repo.foreignTradeIds.add('t1');

      await expectLater(
        repo.requestReview('t1'),
        throwsA(
          isA<AiReviewException>().having(
            (AiReviewException e) => e.failure,
            'failure',
            AiReviewFailure.tradeUnavailable,
          ),
        ),
      );
    });

    test('a refused trade stores nothing', () async {
      final MockAiReviewRepository repo = mockOver(<Trade>[trade()]);
      try {
        await repo.requestReview('missing');
      } on AiReviewException {
        // Expected: the point is that nothing was cached.
      }
      expect(await repo.fetchReview('missing'), isNull);
    });

    test('only the supplied journal is visible', () async {
      final MockAiReviewRepository repo = mockOver(<Trade>[trade(id: 't1')]);
      expect(await repo.fetchReview('t2'), isNull);
      await expectLater(
        repo.requestReview('t2'),
        throwsA(isA<AiReviewException>()),
      );
    });

    test('a review never carries another account identifier', () async {
      final AiReview review =
          await mockOver(<Trade>[trade()]).requestReview('t1');
      expect(
        review.toRow(userId: 'u1').values.join(),
        isNot(contains('acc-1')),
      );
    });
  });
group('MockAiReviewRepository — sparse and invalid data', () {
    test('a trade with no symbol is refused as incomplete', () async {
      final MockAiReviewRepository repo =
          mockOver(<Trade>[trade(symbol: '')]);
      await expectLater(
        repo.requestReview('t1'),
        throwsA(
          isA<AiReviewException>().having(
            (AiReviewException e) => e.failure,
            'failure',
            AiReviewFailure.incomplete,
          ),
        ),
      );
    });

    test('an explicitly incomplete trade is refused', () async {
      final MockAiReviewRepository repo = mockOver(<Trade>[trade()]);
      repo.incompleteTradeIds.add('t1');
      await expectLater(
        repo.requestReview('t1'),
        throwsA(isA<AiReviewException>()),
      );
    });

    test('a trade with no prices still reviews honestly', () async {
      // Never throws: missing prices are reported as unknown, not invented.
      final AiReview review = MockAiReviewRepository.buildFor(
        trade(entry: null, exit: null, stop: null, target: null),
      );
      expect(review.summary, isNotEmpty);
      expect(review.summary.toLowerCase(), contains('no usable stop'));
    });

    test('a huge result does not break the summary', () {
      final AiReview review =
          MockAiReviewRepository.buildFor(trade(pnl: 9.9e12));
      expect(review.summary, contains('XAUUSD'));
    });

    test('a review never exceeds the shared string caps', () async {
      final AiReview review =
          await mockOver(<Trade>[trade()]).requestReview('t1');
      expect(review.summary.length, lessThanOrEqualTo(600));
      expect(review.leak.length, lessThanOrEqualTo(600));
      expect(review.suggestions.length, lessThanOrEqualTo(6));
    });

    test('the pending repository never resolves', () async {
      // Guards the loading state in the widget suite.
      final _PendingRepository repo = _PendingRepository();
      expect(repo.isStubbed, isFalse);
      expect(repo.fetchReview('t1'), isA<Future<AiReview?>>());
    });
  });
}