import 'package:flutter/material.dart';

import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';

class StatsStrip extends StatelessWidget {
  const StatsStrip({required this.stats, super.key});

  final JournalStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: <Widget>[
          _cell('NET P&L', Formatters.signed(stats.netPnl),
              AppColors.forPnl(stats.netPnl),),
          _divider(),
          _cell('WIN %', Formatters.pct(stats.winRate), AppColors.textPrimary),
          _divider(),
          _cell('PF', stats.profitFactor.toStringAsFixed(2), AppColors.accent),
          _divider(),
          _cell('AVG R', stats.avgR.toStringAsFixed(2), AppColors.textPrimary),
        ],
      ),
    );
  }

  Widget _cell(String label, String value, Color color) => Expanded(
        child: Column(
          children: <Widget>[
            Text(label, style: AppTextStyles.label),
            const SizedBox(height: 6),
            Text(value, style: AppTextStyles.title.copyWith(color: color)),
          ],
        ),
      );

  Widget _divider() =>
      Container(width: 1, height: 28, color: AppColors.divider);
}
