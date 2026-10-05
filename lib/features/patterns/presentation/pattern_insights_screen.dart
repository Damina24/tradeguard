import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/pattern_dimension.dart';
import '../domain/pattern_metrics.dart';
import '../domain/trading_leak.dart';
import '../pattern_providers.dart';
import 'leaks_tab.dart';
import '../widgets/pattern_row_tile.dart';
import '../widgets/pattern_state_view.dart';

/// Pattern views + leaks.
///
/// Two tabs over one read of `v_patterns`. Both consume the same
/// [patternInsightsProvider]; neither computes a statistic, so the pattern table
/// and the leaks list can never disagree about the trader's numbers.
class PatternInsightsScreen extends ConsumerStatefulWidget {
  const PatternInsightsScreen({super.key});

  @override
  ConsumerState<PatternInsightsScreen> createState() =>
      _PatternInsightsScreenState();
}

class _PatternInsightsScreenState extends ConsumerState<PatternInsightsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PatternInsights insights = ref.watch(patternInsightsProvider);
    final int journalTrades = ref.watch(journalTradeCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patterns & Leaks'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Widget>[
            Tab(text: 'PATTERNS'),
            Tab(text: 'LEAKS'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: <Widget>[
          _PatternsTab(insights: insights, journalTrades: journalTrades),
          LeaksTab(insights: insights),
        ],
      ),
    );
  }
}

/// The pattern views: one slice-table per dimension `v_patterns` supports.
class _PatternsTab extends ConsumerWidget {
  const _PatternsTab({required this.insights, required this.journalTrades});

  final PatternInsights insights;
  final int journalTrades;

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
          title: 'No trades to find patterns in',
          message: 'Patterns come from your closed trades. Connect a broker or '
              'import a CSV, and they will appear here.',
        ),
      );
    }

    // Trades exist but the sample is below the reporting floor. Deliberately
    // different wording from the empty state above, because the remedy differs:
    // more trades, not a missing broker connection.
    if (insights.insufficientData) {
      return SingleChildScrollView(
        child: Column(
          children: <Widget>[
            const PatternStateView(
              icon: Icons.query_stats,
              title: 'Not enough data yet',
              message: 'You have trades on record, but not enough of them to '
                  'spot a pattern or a leak. Keep trading and this fills in.',
            ),
            SampleFooter(insights: insights, journalTrades: journalTrades),
          ],
        ),
      );
    }

    final PatternDimension dimension =
        ref.watch(selectedPatternDimensionProvider);
    final PatternSort sort = ref.watch(patternSortProvider);
    final PatternDirection direction = ref.watch(patternDirectionProvider);
    final PatternMetrics metrics =
        ref.watch(patternMetricsProvider(dimension));

    // The dimension selector sits above the scroll area so it stays reachable
    // while a long table scrolls underneath it.
    return Column(
      children: <Widget>[
        const DimensionBar(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: <Widget>[
              SortBar(sort: sort, direction: direction),
              const SizedBox(height: 8),
              if (metrics.isEmpty)
                const PatternStateView(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'Nothing recorded for this view',
                  message: 'No trades fall into this grouping yet.',
                )
              else
                for (final PatternMetric m
                    in PatternMetrics.ranked(metrics.metrics, sort, direction))
                  PatternRowTile(
                    metric: m,
                    leakLabel: leakLabelFor(insights, m),
                    minimumTrades: insights.report.minimumTrades,
                  ),
              SampleFooter(insights: insights, journalTrades: journalTrades),
            ],
          ),
        ),
      ],
    );
  }
}

/// The confidence word for a slice the detector flagged, or null.
///
/// Matches on dimension + label rather than object identity, so the badge follows
/// the slice even though the pattern table and the leak list build separate
/// objects from the same source rows.
String? leakLabelFor(PatternInsights insights, PatternMetric m) {
  for (final TradingLeak leak in insights.leaks) {
    if (leak.dimension == m.dimension && leak.label == m.label) {
      return leak.confidence.label;
    }
  }
  return null;
}

/// Horizontal dimension selector.
class DimensionBar extends ConsumerWidget {
  const DimensionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PatternDimension selected = ref.watch(selectedPatternDimensionProvider);
    return SizedBox(
      height: 48,
      // Horizontal scroll: a 320px phone cannot fit four chips on one line, and
      // squeezing them would clip their labels.
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: <Widget>[
          for (final PatternDimension d in PatternDimension.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(d.label),
                selected: d == selected,
                onSelected: (_) => ref
                    .read(selectedPatternDimensionProvider.notifier)
                    .state = d,
              ),
            ),
        ],
      ),
    );
  }
}

/// Sort controls, so the trader can order the table the way they read it.
class SortBar extends ConsumerWidget {
  const SortBar({required this.sort, required this.direction, super.key});

  final PatternSort sort;
  final PatternDirection direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          // Wrap, not Row: four sort chips plus a direction button exceed 320px.
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final PatternSort s in PatternSort.values)
                ChoiceChip(
                  label: Text(s.label),
                  selected: s == sort,
                  onSelected: (_) =>
                      ref.read(patternSortProvider.notifier).state = s,
                ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        // Icon plus tooltip: the arrow states the direction, so the button does
        // not rely on colour and screen readers get the label too.
        IconButton(
          tooltip: direction.label,
          onPressed: () {
            final PatternDirection next =
                direction == PatternDirection.descending
                    ? PatternDirection.ascending
                    : PatternDirection.descending;
            ref.read(patternDirectionProvider.notifier).state = next;
          },
          icon: Icon(
            direction == PatternDirection.descending
                ? Icons.arrow_downward
                : Icons.arrow_upward,
            size: 18,
          ),
        ),
      ],
    );
  }
}

/// "Showing N trades" — the sample size, stated on the screen itself rather than
/// left for the reader to infer.
class SampleFooter extends StatelessWidget {
  const SampleFooter({
    required this.insights,
    required this.journalTrades,
    super.key,
  });

  final PatternInsights insights;
  final int journalTrades;

  @override
  Widget build(BuildContext context) {
    // A mismatch means `v_patterns` and the `trades` table disagree, which the
    // trader deserves to know rather than have silently averaged away.
    final bool mismatch =
        journalTrades > 0 && journalTrades != insights.sampleTrades;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Based on ${insights.sampleTrades} closed '
            'trade${insights.sampleTrades == 1 ? '' : 's'}',
            style: AppTextStyles.disclaimer,
          ),
          if (mismatch)
            Text(
              'Your trade list holds $journalTrades. Patterns come from the '
              'grouped view, so a difference here is expected.',
              style: AppTextStyles.disclaimer.copyWith(color: AppColors.warning),
            ),
        ],
      ),
    );
  }
}