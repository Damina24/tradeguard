import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/replay_scan.dart';

/// The whole-series sweep for the current setup's shape.
///
/// ## Why this card leads with its sample size
///
/// [ReplayScan] re-anchors the setup on every bar, which means a trend produces a dozen apparent
/// "trades" in a row — the count LOOKS large while the evidence is one market move. So the sample
/// size and the reporting floor are printed above every rate, and below the floor no rate is printed
/// at all. A win rate off three correlated bars is not a weak statistic, it is a misleading one.
///
/// Three states, deliberately distinct:
///
///   * **no setup** — nothing to sweep.
///   * **insufficient data** — trades exist but sit below [ReplayScan.minimumTrades]. Says so plainly
///     and prints the count anyway, because "not enough data" with a number attached is actionable
///     while "not enough data" alone is not.
///   * **ready** — the rates, each with its own denominator on screen.
class ReplayScanCard extends StatelessWidget {
  const ReplayScanCard({
    required this.scan,
    required this.hasSetup,
    super.key,
  });

  final ReplayScan scan;

  /// Whether a setup has been chosen at all. Distinguishes "nothing to sweep" from "swept, found
  /// nothing", which are very different messages.
  final bool hasSetup;

  @override
  Widget build(BuildContext context) {
    if (!hasSetup) {
      return const _Shell(
        icon: Icons.grid_view,
        title: 'No sweep yet',
        message: 'Once a setup is set, every bar in the series is tested against it.',
      );
    }

    if (scan.sampleTrades == 0) {
      return _Shell(
        icon: Icons.trending_flat,
        title: 'Nothing would have traded',
        message: 'Across ${scan.attempts} bar${scan.attempts == 1 ? '' : 's'} the entry '
            'was never reached, so there is no sample to summarise.',
      );
    }

    if (scan.isInsufficientData) {
      return _Shell(
        icon: Icons.query_stats,
        title: 'Not enough trades to judge this setup',
        message: 'Only ${scan.sampleTrades} of the ${scan.attempts} bars produced a '
            'trade, and a finding needs at least ${scan.minimumTrades}. That is not '
            'the same as having no edge — there is simply not enough evidence yet.',
        color: AppColors.warning,
      );
    }

    return _Shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.grid_view, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'EVERY BAR TESTED',
                style: AppTextStyles.label.copyWith(color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${scan.sampleTrades} trades from ${scan.attempts} bars',
            style: AppTextStyles.disclaimer,
          ),
          const SizedBox(height: 14),
          _Stats(scan: scan),
          const SizedBox(height: 12),
          _Breakdown(scan: scan),
          const SizedBox(height: 12),
          const Text(
            'Neighbouring bars share the same market move, so these trades are correlated. '
            'A high win rate across one trend is not evidence of an edge.',
            style: AppTextStyles.disclaimer,
          ),
        ],
      ),
    );
  }
}

/// The headline rates. Every value carries its unit, and an unavailable one shows a dash.
class _Stats extends StatelessWidget {
  const _Stats({required this.scan});

  final ReplayScan scan;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 24,
      runSpacing: 12,
      children: <Widget>[
        _stat('Win rate', _pct(scan.winRatePct), _rateColor(scan.winRatePct)),
        _stat(
          'Avg R',
          _signed(scan.expectancyR),
          AppColors.forPnl(scan.expectancyR ?? 0),
        ),
        _stat(
          'Total R',
          _signed(scan.totalR),
          AppColors.forPnl(scan.totalR ?? 0),
        ),
        _stat('PF', _plain(scan.profitFactorR), AppColors.textPrimary),
      ],
    );
  }

  /// A null rate is neutral, not good and not bad.
  static Color _rateColor(double? rate) {
    if (rate == null) return AppColors.textMuted;
    return rate >= 50 ? AppColors.primary : AppColors.danger;
  }

  Widget _stat(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label.toUpperCase(), style: AppTextStyles.label),
          const SizedBox(height: 2),
          Text(value, style: AppTextStyles.h2.copyWith(color: color)),
        ],
      );

  static String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';

  static String _signed(double? v) =>
      v == null ? '—' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}R';

  static String _plain(double? v) => v == null ? '—' : v.toStringAsFixed(2);
}

/// The win / loss / unresolved split, always all three.
///
/// Unresolved is printed even when it is zero, because a reader checking "do these add up?" should
/// not have to infer the missing category.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.scan});

  final ReplayScan scan;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _row('Targets reached', scan.wins, AppColors.primary),
        _row('Stops hit', scan.losses, AppColors.danger),
        _row('Still open at the end', scan.unresolved, AppColors.warning),
        _row('Entries never reached', scan.unfilled.length, AppColors.textMuted),
      ],
    );
  }

  Widget _row(String label, int count, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            Container(width: 8, height: 8, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: AppTextStyles.muted)),
            Text('$count', style: AppTextStyles.body),
          ],
        ),
      );
}

/// The container, shared by every state so they read as one object.
class _Shell extends StatelessWidget {
  const _Shell({
    this.child,
    this.icon,
    this.title,
    this.message,
    this.color = AppColors.textMuted,
  });

  final Widget? child;
  final IconData? icon;
  final String? title;
  final String? message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: child ??
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title!.toUpperCase(),
                      style: AppTextStyles.label.copyWith(color: color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(message!, style: AppTextStyles.muted),
            ],
          ),
    );
  }
}