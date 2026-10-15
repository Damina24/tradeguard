import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import 'calc_sheet.dart';

/// Trading-session windows in UTC. Used to derive the LIVE badge from the
/// device clock instead of a hardcoded flag.
class SessionWindow {
  const SessionWindow(this.name, this.openUtcMins, this.closeUtcMins);

  final String name;

  /// Minutes since 00:00 UTC.
  final int openUtcMins;
  final int closeUtcMins;

  /// True when [nowUtcMinutes] falls inside the window (handles overnight Asia).
  bool isLive(int nowUtcMinutes) {
    if (openUtcMins <= closeUtcMins) {
      return nowUtcMinutes >= openUtcMins && nowUtcMinutes < closeUtcMins;
    }
    return nowUtcMinutes >= openUtcMins || nowUtcMinutes < closeUtcMins;
  }

  String get rangeLabel =>
      '${_fmt(openUtcMins)} – ${_fmt(closeUtcMins)} UTC';

  static String _fmt(int mins) =>
      '${(mins ~/ 60).toString().padLeft(2, '0')}:${(mins % 60).toString().padLeft(2, '0')}';
}

const List<SessionWindow> sessionWindows = <SessionWindow>[
  SessionWindow('London', 8 * 60, 16 * 60 + 30),
  SessionWindow('New York', 13 * 60 + 30, 22 * 60),
  SessionWindow('Asia', 23 * 60, 8 * 60),
];

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools'),
        // Entry point for task 2.6. The icon is paired with a tooltip so the destination is named
        // for screen readers, not just drawn.
        actions: <Widget>[
          IconButton(
            tooltip: 'Replay a setup bar by bar',
            icon: const Icon(Icons.replay),
            onPressed: () => context.push('/tools/replay'),
          ),
          IconButton(
            tooltip: 'Analyse a chart screenshot',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => context.push('/tools/chart-analysis'),
          ),
        ],
      ),
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
          const Text('SESSIONS', style: AppTextStyles.label),
          const SizedBox(height: 8),
          Builder(
            builder: (BuildContext context) {
              final DateTime nowUtc = DateTime.now().toUtc();
              final int nowMins = nowUtc.hour * 60 + nowUtc.minute;
              return Column(
                children: <Widget>[
                  for (final SessionWindow s in sessionWindows)
                    _session(
                      s.name,
                      s.rangeLabel,
                      s.isLive(nowMins),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'Session times are UTC and indicative.',
            style: AppTextStyles.disclaimer,
          ),
        ],
      ),
    );
  }

  Widget _session(String name, String range, bool live) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(
            live ? Icons.circle : Icons.circle_outlined,
            size: 12,
            color: live ? AppColors.primary : AppColors.textMuted,
          ),
          title: Text(name, style: AppTextStyles.body),
          subtitle: Text(range, style: AppTextStyles.muted),
          trailing: live
              ? Text(
                  'LOCAL ${Formatters.time(DateTime.now())}',
                  style: AppTextStyles.label.copyWith(color: AppColors.primary),
                )
              : const Text('Closed', style: AppTextStyles.muted),
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
