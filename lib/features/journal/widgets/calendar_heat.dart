import 'package:flutter/material.dart';

import '../../../core/models/trade.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';

/// Month grid colored by daily net P&L. Green = profit, red = loss.
class CalendarHeat extends StatelessWidget {
  const CalendarHeat({required this.month, required this.trades, super.key});

  final DateTime month;
  final List<Trade> trades;

  static const List<String> _weekdays = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  Map<int, double> _pnlByDay() {
    final Map<int, double> map = <int, double>{};
    for (final Trade t in trades) {
      final DateTime? c = t.closeTime;
      if (c == null || c.month != month.month || c.year != month.year) continue;
      map.update(c.day, (double v) => v + t.pnl, ifAbsent: () => t.pnl);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final Map<int, double> pnl = _pnlByDay();
    final DateTime first = DateTime(month.year, month.month, 1);
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final int leading = first.weekday - 1; // Mon = 0

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: <Widget>[
          Text(Formatters.monthYear(month), style: AppTextStyles.title),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              for (final String w in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(w, style: AppTextStyles.label),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: leading + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemBuilder: (BuildContext context, int index) {
              if (index < leading) return const SizedBox.shrink();
              final int day = index - leading + 1;
              final double? value = pnl[day];
              final Color bg = value == null
                  ? AppColors.surfaceAlt
                  : (value >= 0
                      ? AppColors.primary.withValues(alpha: 0.25)
                      : AppColors.danger.withValues(alpha: 0.25));
              return Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text('$day', style: AppTextStyles.body),
                      if (value != null)
                        Text(
                          Formatters.moneyShort(value),
                          style: AppTextStyles.label.copyWith(
                            color: AppColors.forPnl(value),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
