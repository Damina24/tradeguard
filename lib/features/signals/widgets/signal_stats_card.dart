import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../replay/domain/price_series_request.dart';
import '../../replay/replay_providers.dart';
import '../domain/signal_stats.dart';
import '../domain/volatility_score.dart';
import '../signal_providers.dart';

/// The signals overview card: the volatility radar (task 3.2) above the
/// verified ledger (task 3.1), as two independent sections of one surface.
///
/// **Radar.** Scores the market bars behind the feed through
/// `signalRadarBarsProvider` — 0…100 with a band word — and renders every
/// state the bar read can be in: still measuring, unreadable, too short, or
/// a score with its provenance (symbol, timeframe, bar count, and whether
/// the bars are synthetic demo data). Below [VolatilityScore.minBars] it
/// says *not measured*; it never prints 0, which would read as "market dead
/// calm". The score carries a "not a prediction" line, because a number
/// derived from past ranges that looks like a forecast is exactly the
/// misreading this product must not invite.
///
/// **Ledger.** States a win rate only above [SignalStats.minimumClosed];
/// below the floor it prints the sample size and no rate at all. A rate off
/// a handful of calls is not a weak statistic, it is a misleading one — and
/// in a product that must never promise a win rate, it is the single most
/// dangerous number on this screen.
///
/// The sections never derive from each other: bars loading must not blank
/// the ledger, and an empty ledger must not hide a measured radar.
class SignalStatsCard extends ConsumerWidget {
  const SignalStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SignalStats stats = ref.watch(signalStatsProvider);
    final SignalFeedState feed = ref.watch(signalFeedProvider);
    final ReplayBarsState bars = ref.watch(signalRadarBarsProvider);
    final PriceSeriesRequest request = ref.watch(signalRadarSeriesProvider);

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
          _RadarSection(bars: bars, request: request, score: stats.volatility),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: AppColors.divider),
          ),
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

/// The VOLATILITY RADAR half of the card.
///
/// Every branch below exists because collapsing any two of them would tell
/// the trader something false: "still fetching" is not "there is no
/// volatility", and "the read failed" is not "the market is quiet". The
/// score itself only ever appears next to its provenance — symbol,
/// timeframe, bar count and synthetic-vs-cached — because a number with no
/// statement of what it measured is indistinguishable from a guess.
class _RadarSection extends StatelessWidget {
  const _RadarSection({
    required this.bars,
    required this.request,
    required this.score,
  });

  /// The bar read, carrying its five-state vocabulary from the replay
  /// feature. Drives which message renders; never itself a number.
  final ReplayBarsState bars;

  /// The series being measured, so the provenance line can name it.
  final PriceSeriesRequest request;

  /// The score, when a usable series produced one. Null is rendered as
  /// "not measured" — never as 0.
  final VolatilityScore? score;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('VOLATILITY RADAR', style: AppTextStyles.label),
        const SizedBox(height: 8),
        if (score != null)
          _measured()
        else if (bars.status == ReplayBarsStatus.loading)
          const Text('Measuring volatility…', style: AppTextStyles.muted)
        else if (bars.status == ReplayBarsStatus.error)
          // Closed-set, trader-safe wording from the repository contract —
          // never a raw backend message.
          Text(bars.failure.message, style: AppTextStyles.muted)
        else
          Text(
            'Not enough bars to measure volatility yet — '
            'the radar needs ${VolatilityScore.minBars} bars '
            '(${bars.series?.barCount ?? 0} available).',
            style: AppTextStyles.muted,
          ),
      ],
    );
  }

  /// Score, band, meter, provenance, drivers and the honesty footnote.
  ///
  /// Also renders the stale-refresh note when the score exists but the last
  /// reload failed: the reading on screen is real, it is just no longer the
  /// newest, and the trader deserves to know that rather than assume it.
  Widget _measured() {
    final VolatilityScore data = score!;
    final Color color = _bandColor(data.band);
    final bool isDemo = bars.isStubbed;
    final DateTime? asOf = bars.series?.asOf;
    final String provenance = isDemo
        ? 'SYNTHETIC DEMO'
        : asOf == null
            ? 'CACHED'
            : 'CACHED · updated ${Formatters.timeAgo(asOf)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              '${data.score}',
              style: AppTextStyles.metric.copyWith(color: color),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(data.band.label, style: AppTextStyles.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: data.score / 100,
            minHeight: 10,
            backgroundColor: AppColors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${request.symbol} ${request.timeframe.label} · '
          '${data.barCount} bars · $provenance',
          style: AppTextStyles.muted,
        ),
        const SizedBox(height: 4),
        Text(
          'ATR ${data.rangePct.toStringAsFixed(2)}% of price · ranges '
          '${data.expansionPct >= 0 ? '+' : ''}'
          '${data.expansionPct.toStringAsFixed(0)}% vs prior '
          '${VolatilityScore.window} bars',
          style: AppTextStyles.muted,
        ),
        if (bars.status == ReplayBarsStatus.error) ...<Widget>[
          const SizedBox(height: 4),
          const Text(
            'Latest refresh failed — showing the last measured reading.',
            style: AppTextStyles.muted,
          ),
        ],
        const SizedBox(height: 6),
        const Text(
          'Derived from recent bar ranges — describes what already '
          'printed, not a prediction.',
          style: AppTextStyles.disclaimer,
        ),
      ],
    );
  }

  /// Band → colour, following the app's existing semantics: green quiet,
  /// amber warning, red loud. Blue for moderate, so green never implies
  /// "safe to trade" — calm ranges are not a recommendation.
  static Color _bandColor(VolatilityBand band) => switch (band) {
        VolatilityBand.calm => AppColors.primary,
        VolatilityBand.moderate => AppColors.accent,
        VolatilityBand.elevated => AppColors.warning,
        VolatilityBand.high => AppColors.danger,
      };
}
