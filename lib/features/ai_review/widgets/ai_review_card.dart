import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/ai_review.dart';
import '../../../core/models/ai_review_band.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../paywall/presentation/paywall_screen.dart';
import '../ai_review_providers.dart';
import '../data/ai_review_repository.dart';

/// The AI Review card on S5 Trade Detail (UI_UX_DESIGN §S5, task 2.5).
///
/// Presentation only. Every string it renders comes from an [AiReview] that was validated in
/// `AiReviewDraft`, and every threshold it applies comes from [AiReviewBand] — this file contains no
/// business logic and no arithmetic on the score.
///
/// Three things this card is careful about:
///
///   * **The offline mock is labelled.** When `isStubbed`, a visible "Offline demo" chip sits beside
///     the model name. A demo review shown unlabelled is indistinguishable from real model output,
///     which is exactly the impression a compliance-sensitive product must not give.
///   * **Failure is never rendered as absence.** A failed request shows its own copy; it does not
///     collapse into the "no review yet" state, which would hide a backend misconfiguration behind
///     an inviting button.
///   * **Meaning is never carried by colour alone.** The band, the win/loss glyph and the status
///     text are all words, so the card survives greyscale and colour-blindness.
class AiReviewCard extends ConsumerWidget {
  const AiReviewCard({required this.tradeId, super.key});

  final String tradeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AiReviewState state = ref.watch(aiReviewProvider(tradeId));
    // Prime the Pro gate (see SignalsScreen): reading purchasesProvider here syncs
    // the entitlement when the card builds, so the first "Get AI review" / Refresh
    // tap reads the real isPro instead of the notifier's initial false.
    ref.watch(purchasesProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _header(context, ref, state),
          const SizedBox(height: 12),
          _body(context, ref, state),
          const SizedBox(height: 12),
          // Compliance. AI output is a risk surface, so the disclaimer sits on the card itself
          // rather than only on the signals and paywall screens named in AGENTS.md.
          const Text(
            'AI review is educational only. It is generated from this trade\'s recorded figures, '
            'is not advice, and cannot predict future results. ${AppStrings.riskDisclaimer}',
            style: AppTextStyles.disclaimer,
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, WidgetRef ref, AiReviewState state) {
    final bool busy = state.isLoading;
    final AiReview? review = state.review;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(
          Icons.auto_awesome_outlined,
          size: 18,
          color: AppColors.accent,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('AI REVIEW', style: AppTextStyles.label),
              const SizedBox(height: 4),
              // The model name is stated so the trader knows what wrote the text. It is a label,
              // not a feature claim.
              Text(
                review?.model ?? 'gpt-4o-mini',
                style: AppTextStyles.muted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (busy)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (review != null)
          TextButton(
            onPressed: () => _requestReview(context, ref),
            child: const Text('Refresh'),
          ),
      ],
    );
  }

  /// Requests a fresh AI review, unless the trader is not Pro — in which case
  /// the paywall is shown and no request is made.
  ///
  /// Gate: AI Trade Review requires Pro.
  void _requestReview(BuildContext context, WidgetRef ref) {
    if (!ref.read(purchasesProvider).isPro) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => const PaywallScreen(),
      );
      return;
    }
    ref.read(aiReviewProvider(tradeId).notifier).request();
  }

  Widget _body(BuildContext context, WidgetRef ref, AiReviewState state) {
    final AiReview? review = state.review;

    // A failure is a BANNER, not a replacement. When a previous review is still in state, the
    // trader keeps seeing it: losing their stored feedback because a refresh failed would be a
    // worse outcome than the failure itself. When there is no review to keep, the failure takes
    // the whole body — and crucially it is NOT the `_Prompt`, so a backend misconfiguration can
    // never hide behind an inviting "Get AI review" button.
    if (state.status == AiReviewStatus.failed && review == null) {
      return _Failure(message: state.failure?.message ?? AiReviewFailure.failed.message);
    }

    if (state.isLoading && review == null) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(height: 24),
          Center(
            child: Column(
              children: <Widget>[
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(height: 12),
                Text('Reviewing this trade…', style: AppTextStyles.muted),
              ],
            ),
          ),
        ],
      );
    }

    if (review == null) {
      return _Prompt(
        onRequest: () => _requestReview(context, ref),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (state.status == AiReviewStatus.failed) ...<Widget>[
          _Failure(
            message: state.failure?.message ?? AiReviewFailure.failed.message,
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),
        ],
        _ReviewBody(review: review, isStubbed: state.isStubbedReview),
      ],
    );
  }
}

/// The initial state: nothing has been requested yet.
///
/// This is an OFFER, not an empty result. A new trader who has not asked for a review must not be
/// shown the same card as one whose review failed.
class _Prompt extends StatelessWidget {
  const _Prompt({required this.onRequest});

  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Get a written review of how this trade was executed: what went right, the most likely '
          'process weakness, and a few changes to make next time.',
          style: AppTextStyles.body,
        ),
        const SizedBox(height: 12),
        SizedBox(
          // Full width so the tap target is comfortable on a 320dp screen.
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onRequest,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Get AI review'),
          ),
        ),
      ],
    );
  }
}

/// A failure notice. Always rendered ABOVE the review it interrupted, never instead of it.
class _Failure extends StatelessWidget {
  const _Failure({required this.message});

  /// Trader-safe by construction: [AiReviewFailure.message] is a closed set of hand-written
  /// strings, never a backend message.
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.error_outline, size: 18, color: AppColors.warning),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: AppTextStyles.body),
        ),
      ],
    );
  }
}

/// The rendered review.
class _ReviewBody extends StatelessWidget {
  const _ReviewBody({required this.review, required this.isStubbed});

  final AiReview review;
  final bool isStubbed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _scoreRow(),
        const SizedBox(height: 14),
        Text(review.summary, style: AppTextStyles.body),
        const SizedBox(height: 12),
        Container(height: 1, color: AppColors.divider),
        const SizedBox(height: 12),
        const Text('MOST LIKELY LEAK', style: AppTextStyles.label),
        const SizedBox(height: 6),
        Text(review.leak, style: AppTextStyles.body),
        if (review.hasSuggestions) ...<Widget>[
          const SizedBox(height: 14),
          const Text('SUGGESTIONS', style: AppTextStyles.label),
          const SizedBox(height: 6),
          for (final String suggestion in review.suggestions) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 6, right: 6),
                  child:
                      Icon(Icons.circle, size: 4, color: AppColors.textMuted),
                ),
                Expanded(child: Text(suggestion, style: AppTextStyles.body)),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ] else ...<Widget>[
          const SizedBox(height: 12),
          // A distinct state: "the model had nothing to add" is not "the suggestions failed to load".
          const Text(
            'No further suggestions for this trade.',
            style: AppTextStyles.muted,
          ),
        ],
      ],
    );
  }

  /// The score, its band and the model's name.
  ///
  /// The band is stated in words and paired with an icon, so the reading never depends on colour.
  Widget _scoreRow() => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('EXECUTION SCORE', style: AppTextStyles.label),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    // An unscored review shows a dash, not a zero: a zero would read as a verdict
                    // about a trade nobody assessed.
                    review.band == AiReviewBand.unscored
                        ? '—'
                        : '${review.score}',
                    style: AppTextStyles.h2
                        .copyWith(color: _bandColor(review.band)),
                  ),
                  const SizedBox(width: 4),
                  if (review.band != AiReviewBand.unscored)
                    const Text('/100', style: AppTextStyles.muted),
                ],
              ),
            ],
          ),
          const Spacer(),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _bandIcon(review.band),
                      size: 14,
                      color: _bandColor(review.band),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        review.band.label.toUpperCase(),
                        style: AppTextStyles.label
                            .copyWith(color: _bandColor(review.band)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (isStubbed) ...<Widget>[
                  const SizedBox(height: 4),
                  // Unmissable: a demo review must never be mistaken for model output.
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.accent),
                    ),
                    child: Text(
                      'OFFLINE DEMO',
                      style:
                          AppTextStyles.label.copyWith(color: AppColors.accent),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );

  static Color _bandColor(AiReviewBand band) => switch (band) {
        AiReviewBand.strong => AppColors.primary,
        AiReviewBand.mixed => AppColors.warning,
        AiReviewBand.weak => AppColors.danger,
        AiReviewBand.unscored => AppColors.textMuted,
      };

  static IconData _bandIcon(AiReviewBand band) => switch (band) {
        AiReviewBand.strong => Icons.check_circle_outline,
        AiReviewBand.mixed => Icons.remove_circle_outline,
        AiReviewBand.weak => Icons.error_outline,
        AiReviewBand.unscored => Icons.help_outline,
      };
}
