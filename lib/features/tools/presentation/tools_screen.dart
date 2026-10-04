import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import 'calc_sheet.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          const Text('CALCULATORS', style: AppTextStyles.label),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: const <Widget>[
              _CalcTile(
                type: CalcType.lot,
                icon: Icons.straighten,
                title: 'Lot Size',
                subtitle: 'Risk-based sizing',
              ),
              _CalcTile(
                type: CalcType.rr,
                icon: Icons.balance,
                title: 'Risk / Reward',
                subtitle: 'R:R ratio',
              ),
              _CalcTile(
                type: CalcType.margin,
                icon: Icons.account_balance_wallet,
                title: 'Margin',
                subtitle: 'Required margin',
              ),
              _CalcTile(
                type: CalcType.drawdown,
                icon: Icons.trending_down,
                title: 'Drawdown Sim',
                subtitle: 'Survivable lots',
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('ECONOMIC CALENDAR', style: AppTextStyles.label),
          const SizedBox(height: 8),
          _event('USD', 'Non-Farm Payrolls', 'High', '14:30'),
          _event('EUR', 'ECB Rate Decision', 'High', '13:45'),
          _event('GBP', 'CPI y/y', 'Medium', '08:00'),
          _event('USD', 'FOMC Minutes', 'High', '20:00'),
          const SizedBox(height: 20),
          const Text('SESSIONS', style: AppTextStyles.label),
          const SizedBox(height: 8),
          _session('London', '08:00', '16:30', true),
          _session('New York', '13:30', '22:00', false),
          _session('Asia', '23:00', '08:00', false),
          const SizedBox(height: 12),
          const Text(
            'Session times are UTC and indicative. Calendar data is factual and not '
            'editorial news.',
            style: AppTextStyles.disclaimer,
          ),
        ],
      ),
    );
  }

  Widget _event(String cur, String name, String impact, String time) {
    final Color color = switch (impact) {
      'High' => AppColors.danger,
      'Medium' => AppColors.warning,
      _ => AppColors.textMuted,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.surfaceAlt,
          child: Text(cur, style: AppTextStyles.label),
        ),
        title: Text(name, style: AppTextStyles.body),
        subtitle: Text('$impact impact', style: AppTextStyles.muted.copyWith(color: color)),
        trailing: Text(time, style: AppTextStyles.body),
      ),
    );
  }

  Widget _session(String name, String open, String close, bool live) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(
            live ? Icons.circle : Icons.circle_outlined,
            size: 12,
            color: live ? AppColors.primary : AppColors.textMuted,
          ),
          title: Text(name, style: AppTextStyles.body),
          subtitle: Text('$open – $close UTC', style: AppTextStyles.muted),
          trailing: live
              ? Text(
                  'LOCAL ${Formatters.time(DateTime.now())}',
                  style: AppTextStyles.label.copyWith(color: AppColors.primary),
                )
              : null,
        ),
      );
}

class _CalcTile extends StatelessWidget {
  const _CalcTile({
    required this.type,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final CalcType type;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => CalcSheet(type: type),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Icon(icon, color: AppColors.primary),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppTextStyles.title),
                Text(subtitle, style: AppTextStyles.muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
