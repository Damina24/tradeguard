import 'ai_review_band.dart';

/// One stored AI review of one trade.
///
/// This is the row shape `ai_reviews` has always had (`summary`, `leak`, `score`, `suggestions`,
/// `model`), extended by task 2.5 with the two fields the feature actually needs: the trade it
/// belongs to, and the prompt contract it was generated under.
///
/// Deliberately a plain data holder with NO review logic in it. The score is not clamped here and
/// the suggestions are not filtered here — that all happens once, in `AiReviewDraft.fromResponse`
/// (see `features/ai_review/domain`), so a value that arrives from the Edge Function, from the
/// mock, or from a future producer is put through identical validation. Clamping in two places is
/// how the card and the row start disagreeing about what score a trade has.
class AiReview {
  const AiReview({
    required this.id,
    required this.summary,
    required this.leak,
    required this.score,
    required this.suggestions,
    this.tradeId = '',
    this.model = 'gpt-4o-mini',
    this.promptVersion,
    this.createdAt,
  });

  /// Row id. Empty for a review that has just been returned by the function and not yet re-read.
  final String id;

  final String summary;
  final String leak;

  /// Execution quality, 0–100. NOT a profit forecast — see [AiReviewBand].
  final int score;

  final List<String> suggestions;
  final String model;

  /// The trade this reviews. Present on every stored row.
  final String tradeId;

  /// Which prompt contract produced this text, so a later prompt change is auditable rather than
  /// silently rewriting history.
  final String? promptVersion;

  final DateTime? createdAt;

  /// The score as a band, so the UI never invents its own thresholds.
  AiReviewBand get band => AiReviewBand.forScore(score);

  /// True when the model had nothing to suggest. Distinguishes "no advice" from "advice failed",
  /// which the card renders differently.
  bool get hasSuggestions => suggestions.isNotEmpty;

  factory AiReview.fromJson(Map<String, dynamic> json) => AiReview(
        id: json['id'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        leak: json['leak'] as String? ?? '',
        score: (json['score'] as num?)?.toInt() ?? 0,
        // PostgREST hands `jsonb` back as a decoded list; the Edge Function hands it back as the
        // same list. Anything that is not a list is treated as "no suggestions" rather than
        // throwing, because a card that fails to render is worse than one missing a bullet.
        suggestions: _suggestions(json['suggestions']),
        tradeId: json['trade_id'] as String? ?? '',
        model: json['model'] as String? ?? 'gpt-4o-mini',
        promptVersion: json['prompt_version'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse(json['created_at'] as String),
      );

  /// Round-trips to the `ai_reviews` column shape.
  ///
  /// [userId] is required because the column is NOT NULL and is the ownership boundary — it comes
  /// from the caller's session, never from anything the user typed.
  Map<String, dynamic> toRow({required String userId}) => <String, dynamic>{
        'user_id': userId,
        'trade_id': tradeId,
        'summary': summary,
        'leak': leak,
        'score': score,
        'suggestions': suggestions,
        'model': model,
        'prompt_version': promptVersion,
      };

  /// Non-string entries are dropped rather than stringified: `[object Object]` rendered as a
  /// piece of trading advice would be worse than one fewer bullet.
  static List<String> _suggestions(Object? raw) {
    if (raw is! List) return const <String>[];
    final List<String> out = <String>[];
    for (final Object? entry in raw) {
      if (entry is String && entry.trim().isNotEmpty) out.add(entry);
    }
    return List<String>.unmodifiable(out);
  }
}
