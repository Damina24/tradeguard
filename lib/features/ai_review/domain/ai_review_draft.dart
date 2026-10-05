import '../../../core/models/ai_review.dart';
import 'ai_review_limits.dart';

/// Validation for anything arriving from the `ai-review` Edge Function.
///
/// Pure, total and side-effect free — no Flutter, no network, no repository. It is the ONE place
/// an untrusted AI response becomes an [AiReview], so the mock, the live client and any future
/// producer are all put through identical rules and the card can never render something the row
/// would not have stored.
///
/// The rules and why each one exists:
///
///   * **A missing summary is a failure, not an empty review.** Null here means the caller shows
///     its error state. Rendering a card with a blank body would claim the model reviewed the
///     trade and found nothing, which is a different and false statement.
///   * **The score is clamped into 0..100** so a hallucinated `9999` cannot reach a widget that
///     assumes a percentage.
///   * **Strings are capped and whitespace-collapsed.** Model output routinely contains the
///     literal `\n\n` and double spaces; without this a card can grow unbounded and a 40KB
///     paragraph would be laid out as one line.
///   * **Non-string suggestions are dropped, not stringified.**
class AiReviewDraft {
  const AiReviewDraft._();

  /// Validates a decoded `ai-review` response body.
  ///
  /// Returns null when the response is unusable. [tradeId] is stamped onto the result so the
  /// review can be cached against the trade it belongs to without the caller reassembling it.
  static AiReview? fromResponse(
    Map<String, dynamic> json, {
    required String tradeId,
  }) {
    final String summary = _clean(
      json['summary'],
      AiReviewLimits.maxSummaryChars,
    );
    if (summary.isEmpty) return null;

    final String leak = _clean(json['leak'], AiReviewLimits.maxLeakChars);

    return AiReview(
      id: json['id'] as String? ?? '',
      summary: summary,
      leak: leak.isEmpty ? AiReviewLimits.noLeak : leak,
      score: clampScore(json['score']),
      suggestions: _suggestions(json['suggestions']),
      tradeId: tradeId,
      model: json['model'] as String? ?? AiReviewLimits.model,
      promptVersion:
          json['prompt_version'] as String? ?? AiReviewLimits.promptVersion,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }

  /// Coerces any score input into a whole number inside 0..100.
  ///
  /// Public and total because the score is also validated when a stored row is read back, and a
  /// row written before these rules existed may hold anything.
  static int clampScore(Object? raw) {
    double? value;
    if (raw is num) {
      value = raw.toDouble();
    } else if (raw is String) {
      value = double.tryParse(raw.trim());
    }
    if (value == null || value.isNaN || value.isInfinite) {
      return AiReviewLimits.neutralScore;
    }
    final int rounded = value.round();
    if (rounded < AiReviewLimits.minScore) return AiReviewLimits.minScore;
    if (rounded > AiReviewLimits.maxScore) return AiReviewLimits.maxScore;
    return rounded;
  }

  /// Whitespace-collapses and caps a single AI-authored string.
  ///
  /// Collapsing first and capping second matters: a string that is 5000 characters of newlines
  /// collapses to empty and is treated as absent, rather than being capped to 240 blank
  /// characters that would render as a blank bullet.
  static String _clean(Object? raw, int max) {
    if (raw is! String) return '';
    final String collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= max) return collapsed;
    return collapsed.substring(0, max);
  }

  static List<String> _suggestions(Object? raw) {
    if (raw is! List) return const <String>[];
    final List<String> out = <String>[];
    for (final Object? entry in raw) {
      if (entry is! String) continue;
      final String cleaned = _clean(entry, AiReviewLimits.maxSuggestionChars);
      if (cleaned.isEmpty) continue;
      out.add(cleaned);
      if (out.length >= AiReviewLimits.maxSuggestions) break;
    }
    return List<String>.unmodifiable(out);
  }
}
