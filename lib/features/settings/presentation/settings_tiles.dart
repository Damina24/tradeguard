import 'package:flutter/material.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Small stateless helpers for the Settings screen (kept out of the widget tree).
class SettingsTiles {
  SettingsTiles._();

  static Widget profile({required VoidCallback onUpgrade}) => Container(
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
                  const Text('Demo Trader', style: AppTextStyles.title),
                  Text(
                    AppConfig.useMock ? 'Free plan • demo mode' : 'Free plan',
                    style: AppTextStyles.muted,
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onUpgrade, child: const Text('Upgrade')),
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

  static Future<void> confirmDelete(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently removes your profile, broker connections, trades, '
          'snapshots and screenshots within 30 days. Subscriptions must be cancelled '
          'separately in the store. This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      snack(context, 'Deletion requested. Processed within 30 days.');
    }
  }
}
