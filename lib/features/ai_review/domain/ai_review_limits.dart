/// Caps applied to every AI-authored string before it is stored or rendered.
///
/// These mirror `supabase/functions/ai-review/shared.ts` on purpose. The function is the outer
/// boundary (it protects the database), this is the inner one (it protects the UI from a response
/// that arrived by some other route). Neither is sufficient alone, and both must agree on the
/// numbers, or the card would truncate differently from what was stored.
class AiReviewLimits {
  const AiReviewLimits._();

  static const int maxSummaryChars = 600;
  static const int maxLeakChars = 600;
  static const int maxSuggestions = 6;
  static const int maxSuggestionChars = 240;

  static const int minScore = 0;
  static const int maxScore = 100;

  /// What an unreadable score becomes. The midpoint is deliberate: it renders as "Mixed", which is
  /// the honest reading of "we could not tell", whereas 0 would render as a damning verdict about
  /// a trade nobody assessed.
  static const int neutralScore = 50;

  /// Wording used when the model reported no specific leak. Better than an empty string, which
  /// would render as a blank field the trader has to interpret.
  static const String noLeak = 'None identified.';

  /// Prompt contract the client was built against.
  static const String promptVersion = 'ai-review-v1';

  /// The documented model. Shown on the card so a trader knows what wrote the text.
  static const String model = 'gpt-4o-mini';
}
