import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.accent,
    super.key,
  });

  final String label;
  final String value;
  final String sub;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: AppTextStyles.label),
          const SizedBox(height: 8),
          Text(value, style: AppTextStyles.h2.copyWith(color: accent)),
          const SizedBox(height: 2),
          Text(sub, style: AppTextStyles.muted),
        ],
      ),
    );
  }
}
