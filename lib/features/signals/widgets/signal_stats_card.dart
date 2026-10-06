import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/signal_stats.dart';
import '../signal_providers.dart';

/// Verified ledger over closed signals: what the posted calls actually did.
///
/// States a win rate only above [SignalStats.minimumClosed]; below the floor
/// it prints the sample size and no rate at all. A rate off a handful of
/// calls is not a weak statistic, it is a misleading one — and in a product
/// that must never promise a win rate, it is the single most dangerous number
/// on this screen.
class SignalStatsCard extends ConsumerWidget {
  const SignalStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SignalStats stats = ref.watch(signalStatsProvider);
    final SignalFeedState feed = ref.watch(signalFeedProvider);

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
          const Text('VERIFIED LEDGER', style: AppTextStyles.label),
          const SizedBox(height: 8),
          if (feed.status == SignalFeedStatus.loading)
            const Text('Loading ledger…', style: AppTextStyles.muted)
          else if (feed.status == SignalFeedStatus.error)
            const Text(
              'Ledger unavailable — the feed could not be read.',
              style: AppTextStyles.muted,
            )
          else if (stats.total == 0)
            const Text('No signals posted yet.', style: AppTextStyles.muted)
          else ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  stats.closed.toString(),
                  style:
                      AppTextStyles.metric.copyWith(color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'closed of ${stats.total} posted'
                    '${stats.active > 0 ? ' • ${stats.active} live' : ''}',
                    style: AppTextStyles.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _row('Net pips', _signedPips(stats.netPips)),
            _row('Avg per closed call', _avgPips(stats.avgPips)),
            _row('Wins / losses', '${stats.wins} / ${stats.losses}'),
            const SizedBox(height: 4),
            if (stats.winRate == null)
              Text(
                stats.closed == 0
                    ? 'Win rate appears after the first closed calls are recorded.'
                    : 'Win rate appears after ${SignalStats.minimumClosed} '
                        'closed calls (currently ${stats.closed}).',
                style: AppTextStyles.muted,
              )
            else
              Text(
                'Win rate ${stats.winRate!.toStringAsFixed(1)}% '
                'over ${stats.closed} closed calls',
                style: AppTextStyles.body,
              ),
          ],
        ],
      ),
    );
  }

  static String _signedPips(double pips) =>
      '${pips >= 0 ? '+' : ''}${pips.toStringAsFixed(0)} pips';

  static String _avgPips(double? avg) => avg == null ? '—' : _signedPips(avg);

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label, style: AppTextStyles.muted),
            Text(value, style: AppTextStyles.body),
          ],
        ),
      );
}
