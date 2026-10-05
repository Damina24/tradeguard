import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/trade.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../domain/trade_metrics.dart';
import '../widgets/calendar_heat.dart';
import '../widgets/stats_strip.dart';
import 'trade_detail_screen.dart';

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
          const _TradeList(),
        ],
      ),
    );
  }
}

/// The list itself, which owns the loading / empty / error / populated states.
///
/// Split out so each state can be driven and asserted on its own.
class _TradeList extends ConsumerWidget {
  const _TradeList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TradesNotifier notifier = ref.watch(tradesProvider.notifier);
    // Watching `.notifier` alone does not rebuild when the repository answers.
    final List<Trade> trades = ref.watch(tradesProvider);
    final bool loaded = notifier.loaded;

    // `tradesProvider` starts empty, so an empty list before the repository has answered must
    // not be reported as "you have no trades".
    if (!loaded && trades.isEmpty) return const _LoadingState();
    if (notifier.error != null) return const _ErrorState();
    if (trades.isEmpty) return const _EmptyState();

    return Column(
      children: <Widget>[
        for (final Trade t in trades.take(30)) _TradeRow(trade: t),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
/// No trades — but says *why*, because "empty" and "not connected yet" need different actions.
///
/// The distinction is knowable from the accounts the repository returned: if no account has a
/// broker link, nothing has ever been imported or synced, and "connect a broker" is the useful
/// instruction. Otherwise the trader genuinely has no trades yet.
class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final bool anyConnected =
        accounts.any((a) => (a.metaapiAccountId ?? '').isNotEmpty);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Column(
        children: <Widget>[
          const Icon(Icons.inbox_outlined, size: 36, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            anyConnected ? 'No trades yet' : 'No broker connected',
            style: AppTextStyles.title,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            anyConnected
                ? 'Trades appear here once your broker syncs. You can also import a '
                    'CSV of your trade history.'
                : 'Connect a broker account and trades will sync here automatically. '
                    'You can also import a CSV.',
            style: AppTextStyles.muted,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// The repository failed.
///
/// Generic copy on purpose: the raw exception can name tables, constraints or a provider —
/// none of which helps the trader, and some of which must not be shown at all. The exception is
/// still on `TradesNotifier.error` for logs and tests.
class _ErrorState extends ConsumerWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Column(
        children: <Widget>[
          const Icon(Icons.cloud_off, size: 36, color: AppColors.warning),
          const SizedBox(height: 12),
          const Text(
            'Could not load your trades',
            style: AppTextStyles.title,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Check your connection and try again.',
            style: AppTextStyles.muted,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => ref.read(tradesProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// One row.
///
/// Win and loss are signalled three ways — a signed number, an arrow glyph and colour — so the
/// distinction survives colour-blindness and a greyscale screenshot.
class _TradeRow extends StatelessWidget {
  const _TradeRow({required this.trade});

  final Trade trade;

  @override
  Widget build(BuildContext context) {
    final bool win = TradeMetrics.of(trade).isWin;
    final Color color = AppColors.forPnl(trade.pnl);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TradeDetailScreen(tradeId: trade.id),
          ),
        ),
        leading: Icon(
          win ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          color: color,
          size: 26,
          semanticLabel: win ? 'Win' : 'Loss',
        ),
        title: Row(
          children: <Widget>[
            // Expanded (tight) for the symbol and Flexible (loose) for the P&L. A loose
            // Flexible on the symbol lets it claim the space the P&L needs; and if the two
            // fixed children (direction + P&L) alone exceed the row on a 320px phone, the P&L
            // is what gives way. Both ellipsize, so the row cannot overflow at any width.
            Expanded(
              child: Text(
                trade.symbol,
                style: AppTextStyles.title,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              trade.direction == TradeDirection.long ? 'BUY' : 'SELL',
              style: AppTextStyles.label,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                Formatters.signed(trade.pnl),
                style: AppTextStyles.title.copyWith(color: color),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${trade.lots} lots • '
          '${trade.closeTime == null ? 'open' : Formatters.date(trade.closeTime!)}'
          '${trade.grade == null ? '' : ' • Grade ${trade.grade}'}',
          style: AppTextStyles.muted,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
      ),
    );
  }
}
