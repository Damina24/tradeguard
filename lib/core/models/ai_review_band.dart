/// How an AI review score reads, in words.
///
/// Lives beside `AiReview` in `core/models` because it is part of that model's own vocabulary —
/// the band is a property of the score, not of the feature that displays it. Putting it in a
/// feature would force `core` to depend on `features`, which inverts the layering.
///
/// Centralised here rather than in the card because the thresholds are a CLAIM about the score,
/// and a claim that lives in a widget is a claim a test cannot check. Two surfaces showing the
/// same review must not disagree about whether 55 is "mixed" or "weak".
///
/// The score measures execution quality on the trade that already happened. It is never a
/// prediction — hence no band description implies what happens next.
enum AiReviewBand {
  strong('Strong', 'Process and outcome held up well.'),
  mixed('Mixed', 'Some good process, with something to tighten.'),
  weak('Needs work', 'The process broke down in places worth fixing.'),

  /// No usable score. Rendered as "not scored" rather than as a zero, because a zero would read
  /// as a judgement on a trade we could not actually assess.
  unscored('Not scored', 'No usable score came back with this review.');

  const AiReviewBand(this.label, this.description);

  final String label;
  final String description;

  /// Maps a 0–100 score onto a band.
  ///
  /// Boundaries are inclusive-low: [strong] starts at 70 and [mixed] at 40, so every score in
  /// 0..100 lands in exactly one band. Anything outside the range — a malformed response, a row
  /// written before validation existed — becomes [unscored] rather than being clamped into a
  /// confident-looking verdict.
  static AiReviewBand forScore(int score) {
    if (score < 0 || score > 100) return AiReviewBand.unscored;
    if (score >= 70) return AiReviewBand.strong;
    if (score >= 40) return AiReviewBand.mixed;
    return AiReviewBand.weak;
  }
}
