import '../../../core/models/ai_review.dart';

/// Access to AI trade reviews — the `ai_reviews` table and the `ai-review` Edge Function.
///
/// The seam exists for one reason, and it is the same reason `PatternRepository` has one: **no
/// caller may choose whose review to read.** There is deliberately no `userId` parameter on any
/// method. Identity comes from the authenticated session inside the implementation, and the
/// `ai-review` function independently re-derives it from the verified JWT. A caller that wanted
/// somebody else's review cannot express that request, so there is nothing to get wrong.
abstract class AiReviewRepository {
  /// True when reviews are produced offline, so the card can say so honestly rather than
  /// implying a language model was involved.
  bool get isStubbed;

  /// The stored review for [tradeId], or null when this trade has never been reviewed.
  ///
  /// Null is a real, meaningful answer here — "not reviewed yet" is the initial state of the
  /// card. It is NOT used to report failure: a read that fails throws instead, because rendering
  /// a failure as "no review yet" would quietly discard the trader's stored feedback.
  ///
  /// [tradeId] is the only identifier accepted. There is no way to pass a user id.
  Future<AiReview?> fetchReview(String tradeId);

  /// Asks the `ai-review` Edge Function for a fresh review of [tradeId].
  ///
  /// Throws [AiReviewException] on any failure. Implementations must not surface a raw backend
  /// message: an Edge Function error body can name tables, constraints and model output.
  Future<AiReview> requestReview(String tradeId);
}

/// Why an AI review could not be produced.
///
/// A closed set rather than a raw exception, because the card needs to say something different
/// for "the model is not configured yet" than for "you are offline" — and neither should ever
/// read as "this trade has no review".
enum AiReviewFailure {
  /// No `OPENAI_API_KEY` on the backend. The trader cannot fix this; the product is not deployed.
  notConfigured('AI review is not available on this build yet.'),

  /// The network or the function could not be reached.
  unreachable('Could not reach the AI review service. Try again shortly.'),

  /// The model or the function failed. Deliberately vague: the cause is a backend detail.
  failed('The AI review could not be completed. Try again shortly.'),

  /// The trade is not the caller's, or no longer exists. Both are reported identically so the
  /// endpoint cannot be used to probe for another trader's trade ids.
  tradeUnavailable('That trade is not available for review.'),

  /// The trade exists but is too incomplete to describe (no symbol, no direction, no result).
  incomplete('This trade has too little recorded data to review.');

  const AiReviewFailure(this.message);

  /// Trader-safe wording. Never contains a table name, a constraint, a stack trace or model text.
  final String message;
}

/// A failed AI review request. Carries a [failure] the UI can branch on, never a raw message.
class AiReviewException implements Exception {
  const AiReviewException(this.failure);

  final AiReviewFailure failure;

  String get message => failure.message;

  @override
  String toString() => 'AiReviewException: ${failure.name}';
}
