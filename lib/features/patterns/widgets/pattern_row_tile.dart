import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../domain/pattern_metrics.dart';
import '../domain/trading_leak.dart';

/// One slice of the trader's behaviour.
///
/// Pure presentation: every figure comes from [PatternMetric] and nothing is
/// recomputed here.
///
/// Layout is hostile-input-first. A `symbol` is broker-supplied text and can be
/// absurdly long, and P&L can be six figures, so the label is [Expanded] and
/// ellipsizes while the figures keep their natural width. If even the figures
/// cannot fit — a 320px phone with a five-digit result — the figures give way
/// rather than the row overflowing.
class PatternRowTile extends StatelessWidget {
  const PatternRowTile({
    required this.metric,
    required this.leakLabel,
    this.minimumTrades = 5,
    super.key,
  });

  final PatternMetric metric;

  /// The confidence word to show beside a slice the detector flagged, or null when
  /// it did not flag it. Passed in rather than looked up so the tile cannot run a
  /// second, divergent copy of the detector.
  final String? leakLabel;

  /// The reporting floor, so a thin slice can say so instead of implying the
  /// numbers are comparable with a large one.
  final int minimumTrades;

  @override
  Widget build(BuildContext context) {
    final bool thin = metric.trades < minimumTrades;
    final Color pnlColor = AppColors.forPnl(metric.pnl);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: leakLabel == null ? AppColors.divider : pnlColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // Leading result sign, so the win/loss reading does not rest on the
              // colour of the number beside it.
              Icon(
                metric.pnl >= 0 ? Icons.trending_up : Icons.trending_down,
                size: 16,
                color: pnlColor,
                semanticLabel: metric.pnl >= 0 ? 'Net positive' : 'Net negative',
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  metric.label,
                  style: AppTextStyles.title,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                Formatters.signed(metric.pnl),
                style: AppTextStyles.title.copyWith(color: pnlColor),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Wraps rather than overflows: the sample caveat and the leak badge can
          // arrive in either order and neither may push the row wider.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                '${metric.trades} trade${metric.trades == 1 ? '' : 's'}',
                style: AppTextStyles.label,
              ),
              Text(
                '${(metric.winRate * 100).round()}% won',
                style: AppTextStyles.label,
              ),
              Text(
                LeakEvidence.expectancy(metric.expectancy),
                style: AppTextStyles.label,
              ),
              if (thin)
                Text(
                  'Too few trades to compare',
                  style: AppTextStyles.label.copyWith(color: AppColors.warning),
                ),
              if (leakLabel != null)
                _Badge(label: leakLabel!, color: pnlColor),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small status pill.
///
/// Always text-first: the word carries the meaning and colour only reinforces it,
/// which is what the accessibility rule in `UI_UX_DESIGN.md` asks for.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: AppTextStyles.label.copyWith(color: color),
      ),
    );
  }
}