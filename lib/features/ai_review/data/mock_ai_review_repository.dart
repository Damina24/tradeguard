import '../../../core/models/ai_review.dart';
import '../../../core/models/trade.dart';
import '../../journal/domain/trade_metrics.dart';
// `ReviewReason` is exported by `trade_review.dart`, which is imported for `TradeReview`.
import '../../journal/domain/trade_review.dart';
import '../domain/ai_review_draft.dart';
import '../domain/ai_review_limits.dart';
import 'ai_review_repository.dart';

/// Offline AI reviews, so the whole card is exercisable with no `OPENAI_API_KEY`.
///
/// Three deliberate properties:
///
///   * **Deterministic.** Same trade in, same review out, every run. A mock that used a random
///     score would make widget tests flaky and screenshots unreproducible, and it would misrepresent
///     what the real feature does — the real prompt is pinned at low temperature for the same
///     reason.
///   * **Derived from [TradeReview], not invented.** The deterministic checklist from task 2.3
///     already knows what this trade's process weaknesses are. Re-deriving from it means the mock
///     and the deterministic A–D grade agree about the same trade, instead of the mock quietly
///     becoming a second, contradictory opinion.
///   * **Labelled as offline.** [isStubbed] is true and the card says so, because a demo review
///     shown without that label is indistinguishable from real AI output — exactly the impression
///     a compliance-sensitive product must not give.
class MockAiReviewRepository implements AiReviewRepository {
  MockAiReviewRepository({this.latency = const Duration(milliseconds: 400)});

  final Duration latency;

  /// Resolves the trade being reviewed.
  ///
  /// Injected by [AiReviewNotifier] from the journal the detail screen is already showing, rather
  /// than being a private copy held here. A mock with its own copy of the trades could drift from
  /// the list on screen and review a different trade than the trader is looking at.
  Trade? Function(String tradeId)? tradesLookup;

  /// Reviews already produced this session, keyed by trade id. Re-requesting returns the same
  /// review, mirroring the live `ON CONFLICT (user_id, trade_id)` upsert.
  final Map<String, AiReview> _cache = <String, AiReview>{};

  /// Ids this mock treats as belonging to another account. Account isolation is driven through
  /// this rather than through a second repository instance, so a test can assert on it directly.
  final Set<String> foreignTradeIds = <String>{};

  /// Ids whose trades are deliberately too sparse to review.
  final Set<String> incompleteTradeIds = <String>{};

  @override
  bool get isStubbed => true;

  @override
  Future<AiReview?> fetchReview(String tradeId) async => _cache[tradeId];

  @override
  Future<AiReview> requestReview(String tradeId) async {
    await Future<void>.delayed(latency);

    if (foreignTradeIds.contains(tradeId)) {
      throw const AiReviewException(AiReviewFailure.tradeUnavailable);
    }

    final Trade? trade = tradesLookup?.call(tradeId);
    if (trade == null) {
      throw const AiReviewException(AiReviewFailure.tradeUnavailable);
    }
    if (incompleteTradeIds.contains(tradeId) || trade.symbol.trim().isEmpty) {
      throw const AiReviewException(AiReviewFailure.incomplete);
    }

    final AiReview review = buildFor(trade);
    _cache[tradeId] = review;
    return review;
  }

  /// The mock's whole "intelligence". Pure, deterministic and static, so it is directly testable
  /// without a repository instance or a clock.
  static AiReview buildFor(Trade trade) {
    final TradeReview review = TradeReview.of(TradeMetrics.of(trade));

    // Score from the deterministic checklist so the mock and the A–D grade cannot disagree.
    // Weighted toward compliance rather than outcome: a trader who kept every rule and still lost
    // is executing well, and a review that punished them for the market would be teaching the
    // wrong lesson.
    final int score = AiReviewDraft.clampScore(review.compliance * 100);

    // The "leak" is the first checklist rule that failed — a real, evidenced weakness rather than
    // a vague guess. [ReviewReason.text] is already trader-safe prose.
    final List<ReviewReason> failed = review.reasons
        .where((ReviewReason r) => !r.passed)
        .toList(growable: false);

    final String leak =
        failed.isEmpty ? AiReviewLimits.noLeak : failed.first.text;

    final List<String> suggestions = failed
        .take(AiReviewLimits.maxSuggestions)
        .map(
          (ReviewReason r) =>
              r.evidence == null ? r.text : '${r.text} (${r.evidence}).',
        )
        .toList(growable: false);

    return AiReviewDraft.fromResponse(
      <String, dynamic>{
        'summary': _summary(trade, review),
        'leak': leak,
        'score': score,
        'suggestions': suggestions,
        'model': AiReviewLimits.model,
        'prompt_version': AiReviewLimits.promptVersion,
      },
      tradeId: trade.id,
    )!;
  }

  static String _summary(Trade trade, TradeReview review) {
    final String outcome = review.metrics.isWin
        ? 'closed in profit'
        : review.metrics.isBreakeven
            ? 'closed break-even'
            : 'closed in loss';
    final double? r = review.metrics.rMultiple;
    final String rText = r == null
        ? 'The export carries no usable stop, so the result in R could not be calculated.'
        : 'The result was '
            '${r >= 0 ? '+' : ''}'
            '${r.toStringAsFixed(2)}R.';
    return '${trade.symbol} $outcome. $rText';
  }
}
