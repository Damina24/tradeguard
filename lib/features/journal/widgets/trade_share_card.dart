import 'package:flutter/material.dart';

import '../../../core/models/trade.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../domain/trade_grade.dart';
import '../domain/trade_review.dart';

/// The shareable trade card.
///
/// Pure presentation: everything it renders comes from a [TradeReview], so the same trade always
/// produces the same card and the widget holds no trading logic of its own.
///
/// Privacy, deliberately:
///   * no account number, no broker login, no MetaAPI id — this card is meant to be screenshotted
///     and posted, and none of those belong in a public image;
///   * only the account *nickname* is shown, and only when one is supplied;
///   * no credentials can reach this widget because nothing on [Trade] is one, and the domain
///     layer never sees any.
///
/// It renders at a fixed logical size, so a future task can wrap it in a `RepaintBoundary` and
/// `toImage` for real export or sharing without the layout moving underneath it.
class TradeShareCard extends StatelessWidget {
  const TradeShareCard({
    required this.review,
    this.accountNickname,
    this.width = 320,
    super.key,
  });

  final TradeReview review;

  /// Display name only. Never a login or an account number.
  final String? accountNickname;

  /// Fixed card width so exported images stay consistent across devices.
  final double width;

  @override
  Widget build(BuildContext context) {
    final Trade t = review.metrics.trade;
    final Color pnlColor = AppColors.forPnl(t.pnl);

    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pnlColor.withValues(alpha: 0.45), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _header(t),
          const SizedBox(height: 18),
          _pnlBlock(t, pnlColor),
          const SizedBox(height: 18),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 14),
          _levels(t),
          const SizedBox(height: 14),
          _footer(t),
        ],
      ),
    );
  }

  Widget _header(Trade t) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  t.symbol,
                  style: AppTextStyles.h2,
                  // A very long symbol must not push the grade off the row.
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  t.direction == TradeDirection.long ? 'LONG' : 'SHORT',
                  style: AppTextStyles.label,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _GradeBadge(grade: review.grade),
        ],
      );

  Widget _pnlBlock(Trade t, Color pnlColor) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('NET RESULT', style: AppTextStyles.label),
                const SizedBox(height: 4),
                // `pnl` is the persisted net; never recomputed here.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Formatters.signed(t.pnl),
                    style: AppTextStyles.metric.copyWith(color: pnlColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _OutcomePill(isWin: review.metrics.isWin),
        ],
      );
Widget _levels(Trade t) {
    final double? r = review.metrics.rMultiple;
    return Row(
      children: <Widget>[
        _miniStat('ENTRY', _price(t.entry)),
        _miniStat('EXIT', _price(t.exit)),
        _miniStat(
          'R',
          r == null ? '—' : '${r >= 0 ? '+' : ''}${r.toStringAsFixed(2)}R',
        ),
      ],
    );
  }

  Widget _footer(Trade t) {
    final String? when = t.closeTime == null ? null : Formatters.date(t.closeTime!);
    final String line = <String>[
      if (accountNickname != null && accountNickname!.isNotEmpty) accountNickname!,
      if (when != null) when,
      'TradeGuard',
    ].join(' · ');
    return Text(
      line,
      style: AppTextStyles.disclaimer,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  Widget _miniStat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: AppTextStyles.label),
            const SizedBox(height: 2),
            Text(
              value,
              style: AppTextStyles.body,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      );

  /// Prices vary in width by an order of magnitude across instruments; 4dp keeps a 5-digit gold
  /// price from overflowing the card.
  static String _price(double? v) => v == null ? '—' : v.toStringAsFixed(4);
}

/// Win/loss stated in words *and* a glyph.
///
/// Colour alone is never the signal: roughly 1 in 12 men has a red-green deficiency, and this
/// card is designed to be screenshotted and posted.
class _OutcomePill extends StatelessWidget {
  const _OutcomePill({required this.isWin});

  final bool isWin;

  @override
  Widget build(BuildContext context) {
    final Color color = isWin ? AppColors.primary : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isWin ? Icons.trending_up : Icons.trending_down,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            isWin ? 'WIN' : 'LOSS',
            style: AppTextStyles.label.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// The A–D letter. Letters are the product's own vocabulary, so no legend is needed.
class _GradeBadge extends StatelessWidget {
  const _GradeBadge({required this.grade});

  final TradeGrade grade;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (grade) {
      TradeGrade.a => AppColors.primary,
      TradeGrade.b => AppColors.accent,
      TradeGrade.c => AppColors.warning,
      TradeGrade.d => AppColors.danger,
    };
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        grade.label,
        style: AppTextStyles.h2.copyWith(color: color),
      ),
    );
  }
}