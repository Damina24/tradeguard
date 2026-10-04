import 'package:flutter/material.dart';

import '../../../core/models/guard_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';

class DailyLossCard extends StatelessWidget {
  const DailyLossCard({required this.status, super.key});

  final GuardStatus status;

  Color get _color {
    if (status.dailyUsedPct >= 90) return AppColors.danger;
    if (status.dailyUsedPct >= 70) return AppColors.warning;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final double fraction = (status.dailyUsedPct / 100).clamp(0.0, 1.0);
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
          const Text('DAILY LOSS USED', style: AppTextStyles.label),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                Formatters.pct(status.dailyUsedPct),
                style: AppTextStyles.metric.copyWith(color: _color),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'of ${Formatters.money(status.dailyLossLimit)}',
                  style: AppTextStyles.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 12,
              backgroundColor: AppColors.surfaceAlt,
              valueColor: AlwaysStoppedAnimation<Color>(_color),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Left today: ${Formatters.money(status.dailyLeft)}',
            style: AppTextStyles.body,
          ),
        ],
      ),
    );
  }
}
