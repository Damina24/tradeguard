import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/trade.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import 'trade_detail_screen.dart';
import '../widgets/calendar_heat.dart';
import '../widgets/stats_strip.dart';

class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Trade> trades = ref.watch(tradesProvider);
    final JournalStats stats = ref.watch(journalStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          StatsStrip(stats: stats),
          const SizedBox(height: 16),
          const Text('P&L CALENDAR', style: AppTextStyles.label),
          const SizedBox(height: 8),
          CalendarHeat(
            month: DateTime.now(),
            trades: trades,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text('RECENT TRADES', style: AppTextStyles.label),
              Text('${trades.length}', style: AppTextStyles.muted),
            ],
          ),
          const SizedBox(height: 8),
          for (final Trade t in trades.take(30))
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TradeDetailScreen(tradeId: t.id),
                  ),
                ),
                title: Row(
                  children: <Widget>[
                    Text(t.symbol, style: AppTextStyles.title),
                    const SizedBox(width: 8),
                    Icon(
                      t.direction == TradeDirection.long
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    const Spacer(),
                    Text(
                      Formatters.signed(t.pnl),
                      style: AppTextStyles.title.copyWith(
                        color: AppColors.forPnl(t.pnl),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  '${t.lots} lots • ${t.session ?? '-'} • '
                  '${t.closeTime == null ? '-' : Formatters.date(t.closeTime!)}'
                  '${t.grade == null ? '' : ' • Grade ${t.grade}'}',
                  style: AppTextStyles.muted,
                ),
                trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}
