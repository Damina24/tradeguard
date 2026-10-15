import 'package:flutter/material.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Small stateless helpers for the Settings screen (kept out of the widget tree).
class SettingsTiles {
  SettingsTiles._();

  static Widget profile({
    required VoidCallback onSubscribe,
    String? email,
    bool isPro = false,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: <Widget>[
            const CircleAvatar(
              backgroundColor: AppColors.surfaceAlt,
              child: Icon(Icons.person, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    AppConfig.useMock ? 'Demo Trader' : (email ?? 'TradeGuard'),
                    style: AppTextStyles.title,
                  ),
                  Text(
                    AppConfig.useMock
                        ? 'Demo access • mock mode'
                        : (isPro ? 'TradeGuard Pro' : 'TradeGuard Pro — inactive'),
                    style: AppTextStyles.muted,
                  ),
                ],
              ),
            ),
            if (!isPro)
              TextButton(
                onPressed: onSubscribe,
                child: const Text('Subscribe'),
              ),
          ],
        ),
      );

  static Widget tile(IconData icon, String title, VoidCallback onTap, {Color? color}) =>
      Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(icon, color: color ?? AppColors.textMuted),
          title: Text(title, style: AppTextStyles.body.copyWith(color: color)),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
          onTap: onTap,
        ),
      );

  static void snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  static void showDisclaimer(BuildContext context) => showDialog<void>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Risk disclaimer'),
          content: const SingleChildScrollView(
            child: Text(AppStrings.riskDisclaimer, style: AppTextStyles.body),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
          ],
        ),
      );
}
