import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/disclaimer_note.dart';
import '../domain/price_bar.dart';
import '../domain/price_series.dart';
import '../domain/price_series_request.dart';
import '../domain/replay_result.dart';
import '../domain/replay_scan.dart';
import '../domain/replay_setup.dart';
import '../replay_providers.dart';
import '../widgets/replay_chart.dart';
import '../widgets/replay_controls.dart';
import '../widgets/replay_scan_card.dart';
import '../widgets/replay_setup_form.dart';
import '../widgets/replay_state_view.dart';
import '../widgets/replay_verdict_card.dart';

/// S-replay — a bar-by-bar backtest of one setup over cached OHLC bars.
///
/// A child route of Tools (S6) rather than a sixth bottom-nav tab, for the same reason
/// `/journal/patterns` is a child of Journal: it is a deeper cut of an existing job, and a tab would
/// steal width from the Guard home screen.
///
/// ## What this screen is careful about
///
///   * **The cursor only reveals a prefix.** [visibleBarsProvider] slices the series, so a bar the
///     trader has not stepped to cannot influence the verdict printed beside it. That is what makes it
///     a replay rather than a static report.
///   * **Failure never renders as absence.** A failed refresh keeps the previous chart and shows the
///     error above it, exactly as `AiReviewNotifier` does with a stored review.
///   * **Provenance is on the chart, not in a footnote.** A generated series carries a visible
///     `SYNTHETIC DEMO` chip; a cached one prints its age. There is no path to a chart that does not
///     say where its bars came from.
///   * **The disclaimer sits on the screen**, because a backtest is a risk surface under
///     `docs/RISK_DISCLAIMER.md` even though AGENTS.md only names paywall, copy-signal, signals and
///     settings.
class ReplayScreen extends ConsumerWidget {
  const ReplayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ReplayBarsState bars = ref.watch(selectedBarsProvider);
    final int cursor = ref.watch(replayCursorProvider);
    final List<PriceBar> visible = ref.watch(visibleBarsProvider);
    final ReplaySetup? setup = ref.watch(replaySetupProvider);
    final ReplayResult? verdict = ref.watch(replayVerdictProvider);
    final ReplayScan scan = ref.watch(replayScanProvider);
    final PriceSeries? series = bars.series;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Replay'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Reload price history',
            icon: const Icon(Icons.refresh),
            onPressed: bars.status == ReplayBarsStatus.loading
                ? null
                : () =>
                    ref.read(replayBarsProvider(ref.read(selectedSeriesProvider)).notifier).load(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _SymbolChips(request: ref.watch(selectedSeriesProvider)),
          const SizedBox(height: 12),
          _ReadState(bars: bars, series: series),
          if (bars.isReady || bars.isStaleFailure) ...<Widget>[
            const SizedBox(height: 16),
            ReplayControls(
              cursor: cursor,
              total: bars.bars.length,
              enabled: bars.isReady,
              onSeek: (int index) =>
                  ref.read(replayCursorProvider.notifier).state = index,
            ),
            const SizedBox(height: 16),
            ReplayChart(bars: visible, setup: setup, result: verdict),
            const SizedBox(height: 16),
            ReplaySetupForm(cursorBar: ref.watch(replayCursorBarProvider)),
            const SizedBox(height: 16),
            ReplayVerdictCard(
              setup: setup,
              result: verdict,
              visibleBars: visible.length,
            ),
            const SizedBox(height: 12),
            ReplayScanCard(scan: scan, hasSetup: setup != null),
            const SizedBox(height: 12),
            const _BacktestDisclaimer(),
          ],
        ],
      ),
    );
  }
}

/// Compliance surface: a backtest is a hypothetical result and must say so on the screen that shows
/// it — not only on the paywall, copy-signal and signals screens AGENTS.md names.
class _BacktestDisclaimer extends StatelessWidget {
  const _BacktestDisclaimer();

  @override
  Widget build(BuildContext context) {
    return const DisclaimerNote(
      text: 'Backtests are hypothetical. They replay historical bars under fixed fill '
          'assumptions, ignore spread and slippage, and cannot predict future results. '
          'Past performance does not indicate future performance, and no trading outcome '
          'is guaranteed. ${AppStrings.riskDisclaimer}',
    );
  }
}

/// The five read states, each with its own words.
///
/// Split out so each can be driven and asserted on independently — the mistake this screen is built to
/// avoid is one grey box that has to mean "loading", "no data", "too short" and "failed" at once.
class _ReadState extends ConsumerWidget {
  const _ReadState({required this.bars, required this.series});

  final ReplayBarsState bars;
  final PriceSeries? series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (bars.status) {
      case ReplayBarsStatus.loading:
        return const ReplayStateView.loading();

      case ReplayBarsStatus.empty:
        return const ReplayStateView(
          icon: Icons.inbox_outlined,
          title: 'No bars cached for this symbol',
          message: 'Nothing has been fetched for this series yet. Try again once the '
              'backend has pulled it.',
        );

      case ReplayBarsStatus.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ReplayStateView.error(
              message: bars.failure.message,
              onRetry: () => ref
                  .read(
                    replayBarsProvider(ref.read(selectedSeriesProvider))
                        .notifier,
                  )
                  .load(),
            ),
            // A failed refresh must not blank a chart the trader is reading.
            if (series != null && series!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Still showing the last bars that loaded.',
                  style:
                      AppTextStyles.disclaimer.copyWith(color: AppColors.warning),
                ),
              ),
          ],
        );

      case ReplayBarsStatus.tooShort:
        return ReplayStateView(
          icon: Icons.short_text,
          title: 'Too few bars to replay',
          message: 'Only ${series?.barCount ?? 0} bars are cached for this series. '
              'A replay needs at least ${ReplayBarsNotifier.minimumBars}, because '
              'the bar that fills an entry cannot also be the bar that exits it.',
        );

      case ReplayBarsStatus.ready:
        return _Provenance(series: series!, isStubbed: bars.isStubbed);
    }
  }
}

/// The symbol chips, plus the timeframe the series actually came from.
class _SymbolChips extends ConsumerWidget {
  const _SymbolChips({required this.request});

  final PriceSeriesRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<PriceSeriesRequest> catalogue = ref.watch(priceCatalogueProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final PriceSeriesRequest s in catalogue)
              ChoiceChip(
                label: Text(s.symbol),
                selected: s.symbol == request.symbol,
                // Switching series resets the cursor and the setup: bar 200 of XAUUSD is meaningless
                // on EURUSD, and a setup whose levels were priced off XAUUSD is meaningless there too.
                onSelected: (_) {
                  ref.read(selectedSeriesProvider.notifier).state = s;
                  ref.read(replayCursorProvider.notifier).state = 0;
                  ref.read(replaySetupProvider.notifier).state = null;
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${request.symbol} · ${request.timeframe.label} bars',
          style: AppTextStyles.disclaimer,
        ),
      ],
    );
  }
}

/// Where the bars came from, and how old they are.
///
/// Mandatory on the ready path. A chart of price with no idea where its data came from is exactly how a
/// demo series gets mistaken for the market; design principle 4 in UI_UX_DESIGN.md asks for the source
/// and a freshness stamp on every live widget, and this is that for the replay.
class _Provenance extends StatelessWidget {
  const _Provenance({required this.series, required this.isStubbed});

  final PriceSeries series;
  final bool isStubbed;

  @override
  Widget build(BuildContext context) {
    final PriceSeriesSource source = series.source;
    final Duration? age = series.ageAt(DateTime.now());

    return Row(
      children: <Widget>[
        Icon(
          source.isDemo ? Icons.science_outlined : Icons.cloud_done_outlined,
          size: 14,
          color: source.isDemo ? AppColors.accent : AppColors.textMuted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            source.isDemo
                ? '${source.label} · ${series.barCount} bars · not real market prices'
                : '${source.label} · ${series.barCount} bars · '
                    '${age == null ? 'age unknown' : 'updated ${_ago(age)} ago'}',
            style: AppTextStyles.disclaimer,
          ),
        ),
        if (isStubbed) const SyntheticDemoChip(),
      ],
    );
  }

  static String _ago(Duration d) {
    if (d.inMinutes < 1) return 'moments';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}