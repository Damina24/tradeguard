import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/signal.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/signal_stats.dart';
import '../signal_providers.dart';
import '../widgets/signal_card.dart';
import '../widgets/signal_stats_card.dart';
import 'copy_confirm_sheet.dart';

/// Signals feed + verified stats (task 3.1) and volatility radar (3.2).
///
/// The feed reads `signalFeedProvider`: the `signals` table in live mode, the
/// offline seed in mock mode. The stats card reads `signalStatsProvider` and
/// states a win rate only above [SignalStats.minimumClosed] closed calls — a
/// ledger too thin to support a rate prints its sample size and no rate at
/// all, never a flattering percentage off three calls.
///
/// The volatility radar lives INSIDE the stats card rather than as its own
/// card here: it is one reading beside the ledger, and a separate card would
/// mean a second place deciding what to show for "bars not ready". The
/// placeholder card this screen once carried showed a hardcoded score with
/// invented news drivers — that has been deleted, not reimplemented,
/// because fabricated newswire text is indistinguishable from real market
/// context on screen.
class SignalsScreen extends ConsumerWidget {
  const SignalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SignalFeedState feed = ref.watch(signalFeedProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            const Text('Signals'),
            const SizedBox(width: 8),
            feed.isStubbed ? const _DemoBadge() : const _LiveBadge(),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          ElevatedButton.icon(
            // Task 3.3 shipped the screen; the button that still announced
            // "unlocks in Phase 3" was a stale claim, not a plan.
            onPressed: () => context.push('/tools/chart-analysis'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('AI Chart Analysis'),
          ),
          const SizedBox(height: 16),
          const SignalStatsCard(),
          const SizedBox(height: 16),
          switch (feed.status) {
            SignalFeedStatus.loading => const _FeedLoading(),
            SignalFeedStatus.empty => const _FeedEmpty(),
            SignalFeedStatus.error => _FeedError(
                onRetry: () =>
                    ref.read(signalFeedProvider.notifier).refresh(),
              ),
            SignalFeedStatus.ready => const SizedBox.shrink(),
          },
          for (final Signal s in feed.signals)
            SignalCard(
              signal: s,
              onCopy: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: AppColors.surface,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (_) => CopyConfirmSheet(signal: s),
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Text(AppStrings.riskDisclaimer, style: AppTextStyles.disclaimer),
          ),
        ],
      ),
    );
  }
}

class _FeedLoading extends StatelessWidget {
  const _FeedLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

/// No signals posted yet. Distinct from a failed read: telling a trader the
/// desk is quiet when in fact the feed could not be read would hide a backend
/// misconfiguration behind an inviting empty screen.
class _FeedEmpty extends StatelessWidget {
  const _FeedEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Text(
        'No signals posted yet. New operator calls appear here.',
        style: AppTextStyles.muted,
      ),
    );
  }
}

/// The feed read failed. Never rendered as "no signals": a failure that looks
/// like an empty desk tells the trader nothing is wrong when the backend may
/// simply be unreachable.
class _FeedError extends StatelessWidget {
  const _FeedError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Could not load signals. Check your connection and try again.',
            style: AppTextStyles.body,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Live operator feed. Shown only when the repository is NOT stubbed, so the
/// screen can never imply live posts while serving the offline seed.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.danger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE',
            style: AppTextStyles.label.copyWith(color: AppColors.danger),
          ),
        ],
      ),
    );
  }
}

/// Offline seed. An unlabelled demo feed is indistinguishable from live
/// operator posts — exactly the impression a compliance-sensitive product must
/// not give.
class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'OFFLINE DEMO',
        style: AppTextStyles.label.copyWith(color: AppColors.warning),
      ),
    );
  }
}
