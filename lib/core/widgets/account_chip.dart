import 'package:flutter/material.dart';

import '../../../core/models/account.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class AccountChip extends StatelessWidget {
  const AccountChip({
    required this.account,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final TradingAccount account;
  final bool selected;
  final VoidCallback onTap;

  Color get _phaseColor => switch (account.phase) {
        AccountPhase.eval => AppColors.accent,
        AccountPhase.funded => AppColors.primary,
        AccountPhase.personal => AppColors.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceAlt : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _phaseColor : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _phaseColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(account.nickname, style: AppTextStyles.title),
                Text(account.phase.name.toUpperCase(), style: AppTextStyles.label),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
