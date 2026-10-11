import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/live_account.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../data/live_account_repository.dart';
import 'shimmer_box.dart';

/// The "Live Account Status" section at the top of the Guard dashboard.
///
/// Shows the broker-reported balance, equity and the open positions, with a
/// connection badge that is GREEN only when the link is up and streaming. It is
/// fed by [liveAccountProvider] and renders its own loading / error / empty
/// states so a slow live read never blocks the guard cards below it (which run
/// off the persisted account, not this snapshot).
class LiveAccountCard extends ConsumerWidget {
  const LiveAccountCard({required this.accountId, super.key});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<LiveAccountData> async =
        ref.watch(liveAccountProvider(accountId));

    return async.when(
      loading: () => const _LiveSkeleton(),
      error: (Object error, StackTrace _) => _LiveError(
        message: _messageFor(error),
        onRetry: () => ref.invalidate(liveAccountProvider(accountId)),
      ),
      data: (LiveAccountData data) => _LiveContent(data: data),
    );
  }

  /// Turns a [LiveAccountException] (or anything else) into a trader-safe line.
  static String _messageFor(Object error) {
    if (error is LiveAccountException) return error.message;
    return 'Could not load live data. Try again shortly.';
  }
}

class _LiveContent extends StatelessWidget {
  const _LiveContent({required this.data});

  final LiveAccountData data;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('LIVE ACCOUNT STATUS', style: AppTextStyles.label),
              const Spacer(),
              _ConnectionBadge(data: data),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _Figure(
                  label: 'BALANCE',
                  value: Formatters.money(data.balance),
                ),
              ),
              Container(width: 1, height: 36, color: AppColors.divider),
              Expanded(
                child: _Figure(
                  label: 'EQUITY',
                  value: Formatters.money(data.equity),
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 14),
          _OpenTrades(data: data),
        ],
      ),
    );
  }
}

/// Balance / equity figure.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: 6),
        Text(value, style: AppTextStyles.h2),
      ],
    );
  }
}

/// The connection badge. GREEN only when [ConnectionState.connected]; amber while
/// syncing; red only for a genuine offline link. A never-linked account is grey.
class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.data});

  final LiveAccountData data;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String label;

    if (!data.linked) {
      color = AppColors.textMuted;
      icon = Icons.link_off;
      label = 'NOT LINKED';
    } else {
      switch (data.connection) {
        case BrokerConnectionState.connected:
          color = AppColors.primary; // the app's success/green
          icon = Icons.check_circle_outline;
          label = BrokerConnectionState.connected.label;
        case BrokerConnectionState.syncing:
          color = AppColors.warning;
          icon = Icons.sync;
          label = BrokerConnectionState.syncing.label;
        case BrokerConnectionState.offline:
          color = AppColors.danger; // red — reserved for offline/error
          icon = Icons.cloud_off;
          label = BrokerConnectionState.offline.label;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.label.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Open-trades block: a count plus a scrollable list, or an empty state.
class _OpenTrades extends StatelessWidget {
  const _OpenTrades({required this.data});

  final LiveAccountData data;

  @override
  Widget build(BuildContext context) {
    final int count = data.positions.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text('OPEN TRADES', style: AppTextStyles.label),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: AppTextStyles.label.copyWith(color: AppColors.textPrimary),
              ),
            ),
            const Spacer(),
            if (count > 0)
              Text(
                'Net ${Formatters.signed(data.openPnl)}',
                style: AppTextStyles.label
                    .copyWith(color: AppColors.forPnl(data.openPnl)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (count == 0)
          const _EmptyTrades()
        else
          // Bounded height so the list scrolls inside the page's ListView without
          // fighting it for gestures.
          SizedBox(
            height: 168,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: count,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppColors.divider, height: 1),
              itemBuilder: (BuildContext c, int i) =>
                  _PositionRow(position: data.positions[i]),
            ),
          ),
      ],
    );
  }
}


/// One open position: symbol, side, lots and current P&L.
class _PositionRow extends StatelessWidget {
  const _PositionRow({required this.position});

  final OpenPosition position;

  @override
  Widget build(BuildContext context) {
    final Color sideColor =
        position.isBuy ? AppColors.primary : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              color: sideColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(position.symbol, style: AppTextStyles.title),
                const SizedBox(height: 2),
                Text(
                  '${position.sideLabel} • ${position.lots.toStringAsFixed(2)} lots '
                  '• @ ${position.openPrice}',
                  style: AppTextStyles.muted,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                Formatters.signed(position.pnl),
                style: AppTextStyles.title
                    .copyWith(color: AppColors.forPnl(position.pnl)),
              ),
              const SizedBox(height: 2),
              Text('now ${position.currentPrice}', style: AppTextStyles.muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyTrades extends StatelessWidget {
  const _EmptyTrades();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: <Widget>[
          Icon(Icons.inbox_outlined, color: AppColors.textMuted, size: 20),
          SizedBox(height: 6),
          Text('No open trades', style: AppTextStyles.body),
          SizedBox(height: 2),
          Text(
            'Open positions will appear here in real time.',
            style: AppTextStyles.muted,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}


class _LiveError extends StatelessWidget {
  const _LiveError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('LIVE ACCOUNT STATUS', style: AppTextStyles.label),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.cloud_off, size: 14, color: AppColors.danger),
                    const SizedBox(width: 6),
                    Text(
                      BrokerConnectionState.offline.label,
                      style:
                          AppTextStyles.label.copyWith(color: AppColors.danger),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(message, style: AppTextStyles.body),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Loading placeholder: shimmering figures and rows in place of live data.
class _LiveSkeleton extends StatelessWidget {
  const _LiveSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ShimmerBox(width: 140, height: 12),
              Spacer(),
              ShimmerBox(width: 84, height: 24, radius: 20),
            ],
          ),
          SizedBox(height: 18),
          Row(
            children: <Widget>[
              ShimmerBox(width: 90, height: 12),
              Spacer(),
              ShimmerBox(width: 90, height: 12),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: <Widget>[
              ShimmerBox(width: 120, height: 22),
              Spacer(),
              ShimmerBox(width: 120, height: 22),
            ],
          ),
          SizedBox(height: 18),
          Divider(color: AppColors.divider, height: 1),
          SizedBox(height: 16),
          ShimmerBox(width: 110, height: 12),
          SizedBox(height: 14),
          ShimmerBox(width: double.infinity, height: 28),
          SizedBox(height: 12),
          ShimmerBox(width: double.infinity, height: 28),
        ],
      ),
    );
  }
}

/// Shared surface for every state of the live card, so the section never changes
/// size as it moves between loading, error and data.
class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
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
}

