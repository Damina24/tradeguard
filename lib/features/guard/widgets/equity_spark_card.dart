import 'package:flutter/material.dart';

import '../../../core/models/account.dart';
import '../../../core/models/guard_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';

class EquitySparkCard extends StatelessWidget {
  const EquitySparkCard({required this.status, super.key});

  final GuardStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.show_chart, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text('EQUITY (24H)', style: AppTextStyles.label),
                const SizedBox(height: 4),
                Text(
                  'Peak ${Formatters.money(status.account.peakEquity)}',
                  style: AppTextStyles.body,
                ),
                Text(
                  status.account.drawdownType == DrawdownType.trailing
                      ? 'Trailing drawdown enabled'
                      : 'Static drawdown',
                  style: AppTextStyles.muted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
