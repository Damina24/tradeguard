import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/account.dart';
import '../../../core/models/trade.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../ai_review/widgets/ai_review_card.dart';
import '../domain/trade_grade.dart';
import '../domain/trade_metrics.dart';
import '../domain/trade_review.dart';
import '../widgets/trade_share_card.dart';

/// Everything known about one trade.
///
/// Presentation only: the numbers come from the persisted [Trade] and the deterministic
/// [TradeMetrics]/[TradeReview]. No arithmetic is done in this file.
class TradeDetailScreen extends ConsumerWidget {
  const TradeDetailScreen({required this.tradeId, super.key});

  final String tradeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TradesNotifier trades = ref.watch(tradesProvider.notifier);
    // Watch the list too: watching only `.notifier` does NOT rebuild when the repository
    // answers, so the screen would stay stuck on "not available" until the user navigated away.
    ref.watch(tradesProvider);
    final Trade? trade = trades.byId(tradeId);

    // Resolution goes through the repository-scoped list. A trade the signed-in user does not
    // own is simply not in it, so "not found" is also the answer for someone else's trade.
    if (trade == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trade')),
        body: const _MissingState(),
      );
    }

    final TradeReview review =
        ref.watch(tradeReviewProvider(tradeId)) ?? TradeReview.of(TradeMetrics.of(trade));
    final TradingAccount? account = ref.watch(accountsProvider.notifier).byId(
      trade.accountId,
    );

    return Scaffold(
      appBar: AppBar(title: Text(trade.symbol)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _Header(trade: trade, review: review),
          const SizedBox(height: 16),
          _LevelsCard(trade: trade, metrics: review.metrics),
          const SizedBox(height: 12),
          _CostsCard(trade: trade),
          const SizedBox(height: 16),
          const Text('REVIEW', style: AppTextStyles.label),
          const SizedBox(height: 8),
          _ReviewCard(review: review),
          const SizedBox(height: 16),
          const Text('GRADE', style: AppTextStyles.label),
          const SizedBox(height: 8),
          _GradeSelector(trade: trade, derived: review.grade),
          const SizedBox(height: 20),
          // Task 2.5 — the AI Review card, placed after the deterministic checklist and grade so
          // the trader reads our own verdict first and the model's opinion second. Presenting the
          // model's view before the reproducible one would let it override a grade the trader can
          // check for themselves.
          const Text('AI REVIEW', style: AppTextStyles.label),
          const SizedBox(height: 8),
          AiReviewCard(tradeId: tradeId),
          const SizedBox(height: 20),
          const Text('SHARE', style: AppTextStyles.label),
          const SizedBox(height: 8),
          Center(
            child: TradeShareCard(
              review: review,
              // Nickname only — never a login or an account number.
              accountNickname: account?.nickname,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'The card shows your nickname and trade figures only. No account number, '
            'broker login or credential is ever included.',
            style: AppTextStyles.disclaimer,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Shown for an id that is not in the repository — unknown, deleted, or another user's.
class _MissingState extends StatelessWidget {
  const _MissingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.search_off, size: 40, color: AppColors.textMuted),
            SizedBox(height: 12),
            Text(
              'Trade not available',
              style: AppTextStyles.title,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 6),
            Text(
              'It may have been removed, or it belongs to a different account.',
              style: AppTextStyles.muted,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
/// The headline: direction, result and grade, all from persisted values.
class _Header extends StatelessWidget {
  const _Header({required this.trade, required this.review});

  final Trade trade;
  final TradeReview review;

  @override
  Widget build(BuildContext context) {
    final Color color = AppColors.forPnl(trade.pnl);
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  trade.direction == TradeDirection.long ? 'LONG' : 'SHORT',
                  style: AppTextStyles.label,
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    // The persisted net, verbatim.
                    Formatters.signed(trade.pnl),
                    style: AppTextStyles.metric.copyWith(color: color),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  review.metrics.isWin
                      ? 'Winner'
                      : review.metrics.isBreakeven
                          ? 'Break-even'
                          : 'Loser',
                  style: AppTextStyles.muted,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              const Text('GRADE', style: AppTextStyles.label),
              const SizedBox(height: 6),
              Text(
                review.grade.label,
                style: AppTextStyles.h1.copyWith(
                  color: _gradeColor(review.grade),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Entry / exit / stop / target, plus size and timing.
class _LevelsCard extends StatelessWidget {
  const _LevelsCard({required this.trade, required this.metrics});

  final Trade trade;
  final TradeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final Duration? held = metrics.heldFor;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _row('Size', '${trade.lots.toStringAsFixed(2)} lots'),
          _row('Entry', _price(trade.entry)),
          _row('Exit', _price(trade.exit)),
          _row('Stop loss', _price(trade.stop)),
          _row('Take profit', _price(trade.target)),
          _row('R multiple', _r(metrics.rMultiple)),
          _row('Moved', metrics.pipsMoved == null
              ? '—'
              : '${metrics.pipsMoved!.toStringAsFixed(1)} pips',),
          _row('Held for', held == null ? '—' : _duration(held)),
          _row(
            'Opened',
            trade.openTime == null ? '—' : _stamp(trade.openTime!),
          ),
          _row(
            'Closed',
            trade.closeTime == null ? '—' : _stamp(trade.closeTime!),
          ),
          if (trade.session != null) _row('Session', trade.session!),
          if (trade.setup != null) _row('Setup', trade.setup!),
        ],
      ),
    );
  }
}

/// The cost breakdown that explains the net figure.
class _CostsCard extends StatelessWidget {
  const _CostsCard({required this.trade});

  final Trade trade;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _row('Gross', Formatters.signed(trade.grossPnl)),
          _row('Commission', Formatters.signed(trade.commission)),
          _row('Swap', Formatters.signed(trade.swap)),
          const Divider(color: AppColors.divider, height: 20),
          _row(
            'Net',
            Formatters.signed(trade.pnl),
            emphasise: true,
          ),
          if (trade.currency != null) _row('Currency', trade.currency!),
        ],
      ),
    );
  }
}
/// The checklist behind the grade, plus a compliance bar.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final TradeReview review;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${review.passedCount} of ${review.totalCount} checks passed',
            style: AppTextStyles.muted,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: review.compliance,
              minHeight: 6,
              backgroundColor: AppColors.surfaceAlt,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.forPnl(review.metrics.netPnl),
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final ReviewReason r in review.reasons)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    // Check and cross, so the checklist reads without relying on colour.
                    r.passed ? Icons.check_circle : Icons.cancel_outlined,
                    size: 16,
                    color: r.passed ? AppColors.primary : AppColors.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(r.text, style: AppTextStyles.body),
                  ),
                  if (r.evidence != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Text(r.evidence!, style: AppTextStyles.muted),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 10),
          Text(review.grade.description, style: AppTextStyles.disclaimer),
        ],
      ),
    );
  }
}

/// The A–D selector. Writing goes through the repository, never a local-only value.
class _GradeSelector extends ConsumerWidget {
  const _GradeSelector({required this.trade, required this.derived});

  final Trade trade;
  final TradeGrade derived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A hand-set grade wins; otherwise show what the checklist derived.
    final String selected =
        TradeGrade.tryParse(trade.grade)?.label ?? derived.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (final TradeGrade g in TradeGrade.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () => ref
                          .read(tradesProvider.notifier)
                          .updateGrade(trade.id, g.label),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: selected == g.label
                            ? _gradeColor(g)
                            : AppColors.textMuted,
                        side: BorderSide(
                          color: selected == g.label
                              ? _gradeColor(g)
                              : AppColors.divider,
                        ),
                      ),
                      child: Text(g.label),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          trade.grade == null
              ? 'Auto-graded from the checklist. Tap a letter to override.'
              : 'Your grade. Tap a different letter to change it.',
          style: AppTextStyles.disclaimer,
        ),
      ],
    );
  }
}
/// Shared surface so every card stays visually identical.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: child,
      );
}

/// A label/value line. The value shrinks rather than overflowing, because broker prices and
/// P&L values span several orders of magnitude between a cent account and gold.
Widget _row(String label, String value, {bool emphasise = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Text(label, style: AppTextStyles.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: emphasise ? AppTextStyles.title : AppTextStyles.body,
            ),
          ),
        ],
      ),
    );

Color _gradeColor(TradeGrade g) => switch (g) {
      TradeGrade.a => AppColors.primary,
      TradeGrade.b => AppColors.accent,
      TradeGrade.c => AppColors.warning,
      TradeGrade.d => AppColors.danger,
    };

String _price(double? v) => v == null ? '—' : v.toStringAsFixed(4);

String _r(double? v) =>
    v == null ? '—' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}R';

String _stamp(DateTime d) => '${Formatters.date(d)} ${Formatters.time(d)}';

String _duration(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inDays}d ${d.inHours % 24}h';
}
