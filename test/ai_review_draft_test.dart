import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/ai_review.dart';
import 'package:tradeguard/core/models/ai_review_band.dart';
import 'package:tradeguard/features/ai_review/data/ai_review_repository.dart';
import 'package:tradeguard/features/ai_review/domain/ai_review_draft.dart';
import 'package:tradeguard/features/ai_review/domain/ai_review_limits.dart';

/// A response body as the `ai-review` Edge Function returns it.
Map<String, dynamic> response({
  Object? summary = 'Closed in profit with the stop respected.',
  String leak = 'Moved the stop before the entry triggered.',
  Object? score = 72,
  Object? suggestions = const <String>['Set the stop before entry.'],
}) =>
    <String, dynamic>{
      'ok': true,
      'summary': summary,
      'leak': leak,
      'score': score,
      'suggestions': suggestions,
      'model': 'gpt-4o-mini',
      'prompt_version': 'ai-review-v1',
    };

void main() {
  group('AiReviewDraft — normal behaviour', () {
    test('a well-formed response becomes a review', () {
      final AiReview? review =
          AiReviewDraft.fromResponse(response(), tradeId: 't1');

      expect(review, isNotNull);
      expect(review!.summary, contains('Closed in profit'));
      expect(review.leak, contains('Moved the stop'));
      expect(review.score, 72);
      expect(review.suggestions, <String>['Set the stop before entry.']);
      expect(review.tradeId, 't1');
    });

    test('the trade id is stamped onto the result', () {
      final AiReview? review =
          AiReviewDraft.fromResponse(response(), tradeId: 'trade-abc');
      expect(review!.tradeId, 'trade-abc');
    });

    test('the model and prompt version are carried through', () {
      final AiReview? review =
          AiReviewDraft.fromResponse(response(), tradeId: 't1');
      expect(review!.model, 'gpt-4o-mini');
      expect(review.promptVersion, 'ai-review-v1');
    });

    test('parsing is deterministic for the same input', () {
      final AiReview? a = AiReviewDraft.fromResponse(response(), tradeId: 't1');
      final AiReview? b = AiReviewDraft.fromResponse(response(), tradeId: 't1');
      expect(a!.summary, b!.summary);
      expect(a.score, b.score);
      expect(a.suggestions, b.suggestions);
    });

    test('the band is derived from the score', () {
      final AiReview strong =
          AiReviewDraft.fromResponse(response(score: 85), tradeId: 't1')!;
      expect(strong.band, AiReviewBand.strong);
    });
  });

  group('AiReviewDraft — invalid data', () {
    test('a missing summary is a failure, not an empty review', () {
      expect(
        AiReviewDraft.fromResponse(response(summary: ''), tradeId: 't1'),
        isNull,
      );
    });

    test('a whitespace-only summary is a failure', () {
      expect(
        AiReviewDraft.fromResponse(response(summary: '   \n\n '), tradeId: 't1'),
        isNull,
      );
    });

    test('a non-string summary is a failure', () {
      expect(
        AiReviewDraft.fromResponse(response(summary: 42), tradeId: 't1'),
        isNull,
      );
    });

    test('an unreadable score becomes neutral rather than zero', () {
      final AiReview review =
          AiReviewDraft.fromResponse(response(score: 'high'), tradeId: 't1')!;
      expect(review.score, AiReviewLimits.neutralScore);
      expect(review.score, 50);
    });

    test('a null or NaN score becomes neutral', () {
      expect(
        AiReviewDraft.fromResponse(response(score: null), tradeId: 't1')!.score,
        50,
      );
      expect(
        AiReviewDraft.fromResponse(response(score: double.nan), tradeId: 't1')!
            .score,
        50,
      );
    });

    test('a missing leak becomes an explicit none-identified', () {
      final AiReview review =
          AiReviewDraft.fromResponse(response(leak: ''), tradeId: 't1')!;
      expect(review.leak, AiReviewLimits.noLeak);
    });

    test('a non-array suggestions field yields no suggestions', () {
      expect(
        AiReviewDraft.fromResponse(response(suggestions: 'do this'), tradeId: 't1')!
            .suggestions,
        isEmpty,
      );
      expect(
        AiReviewDraft.fromResponse(response(suggestions: null), tradeId: 't1')!
            .suggestions,
        isEmpty,
      );
    });

    test('non-string suggestions are dropped, not stringified', () {
      final AiReview review = AiReviewDraft.fromResponse(
        response(suggestions: <dynamic>[42, null, <String, Object>{'a': 1}]),
        tradeId: 't1',
      )!;
      expect(review.suggestions, isEmpty);
    });

    test('blank suggestions are dropped', () {
      final AiReview review = AiReviewDraft.fromResponse(
        response(suggestions: <String>['  ', 'real advice']),
        tradeId: 't1',
      )!;
      expect(review.suggestions, <String>['real advice']);
    });
  });

  group('AiReviewDraft — boundary values', () {
    test('clampScore holds both ends of the range', () {
      expect(AiReviewDraft.clampScore(0), 0);
      expect(AiReviewDraft.clampScore(100), 100);
    });

    test('a score above the range is clamped down', () {
      // Regression guard: a hallucinated 9999 must never reach a widget that assumes a percentage.
      expect(AiReviewDraft.clampScore(9999), 100);
      expect(
        AiReviewDraft.fromResponse(response(score: 9999), tradeId: 't1')!.score,
        100,
      );
    });

    test('a negative score is clamped up', () {
      expect(AiReviewDraft.clampScore(-5), 0);
      expect(
        AiReviewDraft.fromResponse(response(score: -5), tradeId: 't1')!.score,
        0,
      );
    });

    test('a fractional score is rounded', () {
      expect(AiReviewDraft.clampScore(67.6), 68);
      expect(AiReviewDraft.clampScore(67.4), 67);
    });

    test('a numeric string score is coerced', () {
      expect(AiReviewDraft.clampScore('80'), 80);
    });

    test('an infinite score is neutral, not clamped', () {
      expect(AiReviewDraft.clampScore(double.infinity), 50);
      expect(AiReviewDraft.clampScore(double.negativeInfinity), 50);
    });

    test('over-long text is capped', () {
      final AiReview review = AiReviewDraft.fromResponse(
        response(
          summary: 'a' * (AiReviewLimits.maxSummaryChars + 500),
          leak: 'b' * (AiReviewLimits.maxLeakChars + 500),
          suggestions: <String>[
            'c' * (AiReviewLimits.maxSuggestionChars + 500),
          ],
        ),
        tradeId: 't1',
      )!;

      expect(review.summary.length, AiReviewLimits.maxSummaryChars);
      expect(review.leak.length, AiReviewLimits.maxLeakChars);
      expect(review.suggestions.first.length, AiReviewLimits.maxSuggestionChars);
    });

    test('suggestions are capped in count', () {
      final AiReview review = AiReviewDraft.fromResponse(
        response(
          suggestions: List<String>.generate(40, (int i) => 'tip $i'),
        ),
        tradeId: 't1',
      )!;
      expect(review.suggestions.length, AiReviewLimits.maxSuggestions);
    });

    test('a string of only whitespace collapses to nothing, not a blank cap', () {
      // A 6000-character run of newlines must be treated as absent, not capped to 240 blanks.
      final AiReview? review =
          AiReviewDraft.fromResponse(response(leak: '\n' * 6000), tradeId: 't1');
      expect(review!.leak, AiReviewLimits.noLeak);
    });

    test('internal whitespace is collapsed to single spaces', () {
      final AiReview review =
          AiReviewDraft.fromResponse(response(summary: 'a\n\n  b   c'), tradeId: 't1')!;
      expect(review.summary, 'a b c');
    });
  });

  group('AiReviewBand', () {
    test('boundaries are inclusive-low and total over 0..100', () {
      expect(AiReviewBand.forScore(70), AiReviewBand.strong);
      expect(AiReviewBand.forScore(100), AiReviewBand.strong);
      expect(AiReviewBand.forScore(69), AiReviewBand.mixed);
      expect(AiReviewBand.forScore(40), AiReviewBand.mixed);
      expect(AiReviewBand.forScore(39), AiReviewBand.weak);
      expect(AiReviewBand.forScore(0), AiReviewBand.weak);
    });

    test('every score in range maps to exactly one band', () {
      for (int s = 0; s <= 100; s++) {
        expect(
          AiReviewBand.forScore(s),
          isNot(AiReviewBand.unscored),
          reason: 'score $s must resolve to a real band',
        );
      }
    });

    test('an out-of-range score is unscored, never clamped into a verdict', () {
      // A zero would render as a damning judgement about a trade nobody assessed.
      expect(AiReviewBand.forScore(-1), AiReviewBand.unscored);
      expect(AiReviewBand.forScore(101), AiReviewBand.unscored);
    });

    test('every band has human wording', () {
      for (final AiReviewBand band in AiReviewBand.values) {
        expect(band.label, isNotEmpty);
        expect(band.description, isNotEmpty);
      }
    });

    test('no band description promises an outcome', () {
      // Compliance: the AGENTS guardrails forbid guaranteed-profit language anywhere.
      for (final AiReviewBand band in AiReviewBand.values) {
        final String text = band.description.toLowerCase();
        expect(text, isNot(contains('guarantee')));
        expect(text, isNot(contains('will make')));
        expect(text, isNot(contains('profit')));
        expect(text, isNot(contains('win rate')));
      }
    });
  });

  group('AiReview model', () {
    test('reads a stored row', () {
      final AiReview review = AiReview.fromJson(<String, dynamic>{
        'id': 'r1',
        'user_id': 'u1',
        'trade_id': 't1',
        'summary': 'ok',
        'leak': 'none',
        'score': 61,
        'suggestions': <String>['tip'],
        'model': 'gpt-4o-mini',
        'prompt_version': 'ai-review-v1',
        'created_at': '2026-04-20T12:00:00.000Z',
      });

      expect(review.id, 'r1');
      expect(review.tradeId, 't1');
      expect(review.score, 61);
      expect(review.createdAt, DateTime.utc(2026, 4, 20, 12));
    });

    test('tolerates a sparse row', () {
      final AiReview review =
          AiReview.fromJson(<String, dynamic>{'summary': 'ok'});
      expect(review.score, 0);
      expect(review.suggestions, isEmpty);
      expect(review.tradeId, '');
      expect(review.createdAt, isNull);
    });

    test('an unparseable created_at is null, not a throw', () {
      final AiReview review = AiReview.fromJson(<String, dynamic>{
        'summary': 'ok',
        'created_at': 'not-a-date',
      });
      expect(review.createdAt, isNull);
    });

    test('a non-list suggestions column yields no suggestions', () {
      final AiReview review = AiReview.fromJson(<String, dynamic>{
        'summary': 'ok',
        'suggestions': 'a string',
      });
      expect(review.suggestions, isEmpty);
    });

    test('round-trips to the column shape', () {
      const AiReview review = AiReview(
        id: '',
        summary: 'ok',
        leak: 'none',
        score: 55,
        suggestions: <String>['tip'],
        tradeId: 't1',
      );
      final Map<String, dynamic> row = review.toRow(userId: 'u1');

      expect(row['user_id'], 'u1');
      expect(row['trade_id'], 't1');
      expect(row['summary'], 'ok');
      expect(row['score'], 55);
    });

    test('the row shape carries no credential field', () {
      const AiReview review = AiReview(
        id: '',
        summary: 'ok',
        leak: 'none',
        score: 50,
        suggestions: <String>[],
      );
      final Map<String, dynamic> row = review.toRow(userId: 'u1');
      expect(row.values.join(), isNot(contains('service')));
      expect(row.containsKey('password'), isFalse);
      expect(row.containsKey('login'), isFalse);
      expect(row.containsKey('metaapi_account_id'), isFalse);
    });

    test('hasSuggestions distinguishes no advice from no review', () {
      const AiReview empty = AiReview(
        id: '',
        summary: 'ok',
        leak: 'none',
        score: 50,
        suggestions: <String>[],
      );
      const AiReview withAdvice = AiReview(
        id: '',
        summary: 'ok',
        leak: 'none',
        score: 50,
        suggestions: <String>['tip'],
      );
      expect(empty.hasSuggestions, isFalse);
      expect(withAdvice.hasSuggestions, isTrue);
    });
  });

  group('AiReviewFailure', () {
    test('every failure has trader-safe wording', () {
      for (final AiReviewFailure failure in AiReviewFailure.values) {
        expect(failure.message, isNotEmpty);
        // A raw backend message names tables and columns; none of that may reach a trader.
        final String text = failure.message.toLowerCase();
        expect(text, isNot(contains('select ')));
        expect(text, isNot(contains('constraint')));
        expect(text, isNot(contains('exception')));
        expect(text, isNot(contains('http')));
        expect(text, isNot(contains('null')));
      }
    });

    test('the not-configured failure names the product, not the secret', () {
      // A trader cannot fix a missing key, and must never be shown the name of a secret.
      final String text = AiReviewFailure.notConfigured.message.toLowerCase();
      expect(text, isNot(contains('key')));
      expect(text, isNot(contains('openai')));
      expect(text, isNot(contains('api')));
    });

    test('a foreign trade and a missing trade share one wording', () {
      // Otherwise the endpoint becomes a probe for whether another trader's trade id exists.
      expect(
        AiReviewFailure.tradeUnavailable.message,
        'That trade is not available for review.',
      );
    });

    test('the exception carries the reason and no raw text', () {
      const AiReviewException e =
          AiReviewException(AiReviewFailure.notConfigured);
      expect(e.failure, AiReviewFailure.notConfigured);
      expect(e.message, AiReviewFailure.notConfigured.message);
      expect(e.toString(), isNot(contains(' at ')));
    });
  });
}