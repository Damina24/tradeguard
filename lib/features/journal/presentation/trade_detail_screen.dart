import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/trade.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';

class TradeDetailScreen extends ConsumerWidget {
  const TradeDetailScreen({required this.tradeId, super.key});

  final String tradeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Trade? trade = ref
        .watch(tradesProvider)
        .where((Trade t) => t.id == tradeId)
        .firstOrNull;

    if (trade == null) {
      return const Scaffold(
        body: Center(child: Text('Trade not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(trade.symbol)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      trade.direction == TradeDirection.long ? 'LONG' : 'SHORT',
                      style: AppTextStyles.label,
                    ),
                    const Spacer(),
                    Text(
                      Formatters.signed(trade.pnl),
                      style: AppTextStyles.h2.copyWith(
                        color: AppColors.forPnl(trade.pnl),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _row('Lots', trade.lots.toStringAsFixed(2)),
                _row('Entry', trade.entry?.toStringAsFixed(4) ?? '-'),
                _row('Exit', trade.exit?.toStringAsFixed(4) ?? '-'),
                _row('Stop', trade.stop?.toStringAsFixed(4) ?? '-'),
                _row('Target', trade.target?.toStringAsFixed(4) ?? '-'),
                _row('Session', trade.session ?? '-'),
                _row('Setup', trade.setup ?? '-'),
                _row('R Multiple', trade.rMultiple?.toStringAsFixed(2) ?? '-'),
                _row(
                  'Closed',
                  trade.closeTime == null ? '-' : Formatters.date(trade.closeTime!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('GRADE', style: AppTextStyles.label),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (final String g in <String>['A', 'B', 'C', 'D'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      onPressed: () => ref
                          .read(tradesProvider.notifier)
                          .updateGrade(trade.id, g),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        foregroundColor: trade.grade == g
                            ? AppColors.primary
                            : AppColors.textMuted,
                        side: BorderSide(
                          color: trade.grade == g
                              ? AppColors.primary
                              : AppColors.divider,
                        ),
                      ),
                      child: Text(g),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.auto_awesome, size: 16, color: AppColors.accent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI Review unlocks in Phase 2 and runs server-side via an Edge '
                    'Function. No broker credentials are ever sent for analysis.',
                    style: AppTextStyles.disclaimer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label, style: AppTextStyles.muted),
            Text(value, style: AppTextStyles.body),
          ],
        ),
      );
}
