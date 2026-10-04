import 'package:flutter/material.dart';

import '../../../core/models/guard_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';

class TodayCard extends StatelessWidget {
  const TodayCard({required this.status, super.key});

  final GuardStatus status;

  @override
  Widget build(BuildContext context) {
    final double pnl = status.account.dailyPnl;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('TODAY P&L', style: AppTextStyles.label),
              const SizedBox(height: 6),
              Text(
                Formatters.signed(pnl),
                style: AppTextStyles.h2.copyWith(color: AppColors.forPnl(pnl)),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              const Text('EQUITY', style: AppTextStyles.label),
              const SizedBox(height: 6),
              Text(Formatters.money(status.account.equity), style: AppTextStyles.title),
            ],
          ),
        ],
      ),
    );
  }
}
