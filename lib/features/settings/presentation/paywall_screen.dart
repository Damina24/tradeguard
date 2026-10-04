import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  static const List<(String, String, String)> _features = <(String, String, String)>[
    ('Accounts', '1', 'Unlimited'),
    ('Live guard push', '—', 'Yes'),
    ('AI reviews / day', '3', 'Unlimited'),
    ('Signals / day', '3', 'VIP'),
    ('Copy-trading', '—', 'Enabled'),
    ('Advanced analytics', '—', 'Yes'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _hero(),
          const SizedBox(height: 20),
          _comparisonTable(),
          const SizedBox(height: 16),
          _lifetimeCard(),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => _info(context, 'Paywall connects to store billing in Phase 4.'),
            child: const Text('Start 7-day free trial'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _info(context, 'Restoring purchases…'),
            child: const Text('Restore purchases'),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Text(AppStrings.riskDisclaimer, style: AppTextStyles.disclaimer),
          ),
        ],
      ),
    );
  }

  void _info(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Widget _hero() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[AppColors.surfaceAlt, AppColors.surface],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('TradeGuard Pro', style: AppTextStyles.h1),
            SizedBox(height: 6),
            Text(
              'Keep the guard on, unlock every signal and journal insight.',
              style: AppTextStyles.body,
            ),
            SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(r'$29.99', style: AppTextStyles.metric),
                Padding(
                  padding: EdgeInsets.only(bottom: 6, left: 4),
                  child: Text('/month', style: AppTextStyles.muted),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text('7-day free trial. Cancel anytime in the store.',
                style: AppTextStyles.muted,),
          ],
        ),
      );

  Widget _lifetimeCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
        ),
        child: const Row(
          children: <Widget>[
            Icon(Icons.workspace_premium, color: AppColors.warning),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Founders lifetime', style: AppTextStyles.title),
                  SizedBox(height: 2),
                  Text(r'$197 once • first 500 traders', style: AppTextStyles.muted),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _comparisonTable() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(flex: 2, child: SizedBox()),
                const Expanded(
                  child: Text('FREE',
                      style: AppTextStyles.label, textAlign: TextAlign.center,),
                ),
                Expanded(
                  child: Text('PRO',
                      style: AppTextStyles.label.copyWith(color: AppColors.primary),
                      textAlign: TextAlign.center,),
                ),
              ],
            ),
            const Divider(color: AppColors.divider, height: 20),
            for (final (String label, String free, String pro) in _features)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: <Widget>[
                    Expanded(flex: 2, child: Text(label, style: AppTextStyles.body)),
                    Expanded(
                      child: Text(free,
                          style: AppTextStyles.muted, textAlign: TextAlign.center,),
                    ),
                    Expanded(
                      child: Text(
                        pro,
                        style: AppTextStyles.body.copyWith(color: AppColors.primary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}
