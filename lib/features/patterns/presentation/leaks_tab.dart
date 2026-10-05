import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/disclaimer_note.dart';
import '../domain/trading_leak.dart';
import '../pattern_providers.dart';
import '../widgets/leak_card.dart';
import '../widgets/pattern_state_view.dart';

/// The leaks tab.
///
/// Five distinct states, each with its own words:
///
///   * loading / error / no trades — shared with the patterns tab, because they
///     describe the *read*, which both tabs depend on;
///   * **not enough data** — trades exist but below the reporting floor. This is
///     the state the spec's honesty rule is really about: it must not be rendered
///     as "no leaks", because a trader with four trades has no evidence either way;
///   * **no leaks found** — the sweep ran over a usable sample and nothing
///     qualified. A real result, stated plainly rather than shown as a blank list.
class LeaksTab extends ConsumerWidget {
  const LeaksTab({required this.insights, super.key});

  final PatternInsights insights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PatternState state = ref.watch(patternStateProvider);

    if (state.status == PatternStatus.loading) {
      return const Center(child: PatternStateView.loading());
    }
    if (state.status == PatternStatus.error) {
      return Center(
        child: PatternStateView.error(
          onRetry: () => ref.read(patternStateProvider.notifier).refresh(),
        ),
      );
    }
    if (state.status == PatternStatus.empty) {
      return const SingleChildScrollView(
        child: PatternStateView(
          icon: Icons.inbox_outlined,
          title: 'No trades to check for leaks',
          message: 'Leaks are recurring weaknesses in your own results. They need '
              'closed trades to find.',
        ),
      );
    }

    if (insights.insufficientData) {
      return const SingleChildScrollView(
        child: PatternStateView(
          icon: Icons.query_stats,
          title: 'Not enough data to identify a leak',
          message: 'Nothing here qualifies as a pattern yet. That is not the same '
              'as having none.',
        ),
      );
    }

    if (insights.leaks.isEmpty) {
      return SingleChildScrollView(
        child: Column(
          children: <Widget>[
            const PatternStateView(
              icon: Icons.verified_outlined,
              title: 'No leaks found',
              message: 'No symbol, session, hour or day is clearly draining your '
                  'results right now.',
            ),
            _SweepFooter(report: insights.report),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        for (final TradingLeak leak in insights.leaks) LeakCard(leak: leak),
        _SweepFooter(report: insights.report),
        const SizedBox(height: 12),
        // Compliance surface: a risk disclaimer belongs on anything that comments
        // on trading performance, alongside the signals and paywall notes.
        const DisclaimerNote(
          text: 'These are patterns in your own recorded results, not advice. A '
              'leak means something recurred often enough to be worth a look — it '
              'is not proof of a cause, and no trading outcome is guaranteed.',
        ),
      ],
    );
  }
}

/// "Reviewed N slices" — shown on the no-leaks path so an empty result reads as
/// "the sweep ran and found nothing" rather than "nothing loaded".
class _SweepFooter extends StatelessWidget {
  const _SweepFooter({required this.report});

  final LeakReport report;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Text(
        'Reviewed ${report.reviewedSlices} symbol, session, hour and day '
        'groupings across ${report.sampleTrades} closed '
        'trade${report.sampleTrades == 1 ? '' : 's'}.',
        style: AppTextStyles.disclaimer,
      ),
    );
  }
}