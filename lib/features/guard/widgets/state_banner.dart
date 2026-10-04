import 'package:flutter/material.dart';

import '../../../core/models/guard_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';

class StateBanner extends StatelessWidget {
  const StateBanner({required this.status, super.key});

  final GuardStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status.state) {
      GuardState.ok => (AppColors.primary, Icons.verified_user),
      GuardState.warn => (AppColors.warning, Icons.warning_amber),
      GuardState.critical => (AppColors.danger, Icons.error_outline),
      GuardState.breach => (AppColors.danger, Icons.gpp_bad),
      GuardState.stale => (AppColors.warning, Icons.history),
      GuardState.error => (AppColors.textMuted, Icons.cloud_off),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${status.state.label}  •  ${status.account.platform.toUpperCase()}'
              '  •  updated ${Formatters.timeAgo(status.asOf)}',
              style: AppTextStyles.muted.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
