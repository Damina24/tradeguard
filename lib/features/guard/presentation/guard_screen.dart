import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/account.dart';
import '../../../core/models/guard_status.dart';
import '../../../core/services/providers.dart';
import '../../../core/services/telemetry_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/account_chip.dart';
import '../widgets/daily_loss_card.dart';
import '../widgets/equity_spark_card.dart';
import '../widgets/live_account_card.dart';
import '../widgets/metric_card.dart';
import '../widgets/state_banner.dart';
import '../widgets/today_card.dart';

class GuardScreen extends ConsumerWidget {
  const GuardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<TradingAccount> accounts = ref.watch(accountsProvider);
    final TradingAccount? selected = ref.watch(selectedAccountProvider);
    final GuardStatus? status = ref.watch(guardStatusProvider);
    // The accounts notifier owns loading/error/loaded. Watching `.notifier` alone does not
    // rebuild when the repository answers, so watch the list too (done above via `accounts`).
    final AccountsNotifier accountsNotifier =
        ref.watch(accountsProvider.notifier);

    // One push per threshold crossing. The monitor de-duplicates, so a 1/min refresh while the
    // trader sits above 70% does not spam.
    ref.listen<GuardStatus?>(
      guardStatusProvider,
      (GuardStatus? previous, GuardStatus? next) {
        if (next == null) return;
        unawaited(ref.read(guardAlertMonitorProvider).onGuardStatus(next));
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guard'),
        actions: <Widget>[
          IconButton(
            onPressed: () {
              ref.read(accountsProvider.notifier).refresh();
              ref.invalidate(guardStatusProvider);
              // Re-pull the live broker read for the selected account so a manual
              // refresh also refreshes balance/equity/positions, not just the guard.
              final TradingAccount? current =
                  ref.read(selectedAccountProvider);
              if (current != null) {
                ref.invalidate(liveAccountProvider(current.id));
              }
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      // A missing [GuardStatus] is ambiguous on its own — the account list may still be loading,
      // may have failed to load, or may be genuinely empty. Each of those is a different screen;
      // showing one spinner for all three is what left the Guard page hanging forever when the
      // accounts query never resolved. Resolve the ambiguity from the notifier's own state.
      body: _buildBody(
        context,
        ref,
        accountsNotifier,
        accounts,
        selected,
        status,
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AccountsNotifier accountsNotifier,
    List<TradingAccount> accounts,
    TradingAccount? selected,
    GuardStatus? status,
  ) {
    // Still loading the very first time: no answer yet, no accounts, no error.
    if (!accountsNotifier.loaded &&
        accounts.isEmpty &&
        accountsNotifier.error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // The accounts read failed. A broken backend must never look like an empty desk or spin.
    if (accountsNotifier.error != null) {
      return _GuardMessage(
        icon: Icons.cloud_off,
        title: 'Could not load your accounts',
        message: 'Check your connection and try again.',
        onRetry: () => ref.read(accountsProvider.notifier).refresh(),
      );
    }

    // Loaded successfully but the trader has no account to guard yet.
    if (accounts.isEmpty) {
      return const _GuardMessage(
        icon: Icons.account_balance_outlined,
        title: 'No accounts yet',
        message:
            'Connect a broker account in Settings to start the equity guard.',
      );
    }

    // Accounts exist but no guard status could be computed (no selection): fall back to the first.
    if (status == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        ref.invalidate(guardStatusProvider);
        final TradingAccount? current = ref.read(selectedAccountProvider);
        if (current != null) {
          ref.invalidate(liveAccountProvider(current.id));
        }
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          SizedBox(
            height: 62,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: accounts.length,
              itemBuilder: (BuildContext c, int i) => AccountChip(
                account: accounts[i],
                selected: accounts[i].id == selected?.id,
                onTap: () => ref
                    .read(selectedAccountIdProvider.notifier)
                    .state = accounts[i].id,
              ),
            ),
          ),
          const SizedBox(height: 8),
          StateBanner(status: status),
          const SizedBox(height: 16),
          // Live broker read: balance, equity, connection health and open
          // positions. Its own loading/error/empty states, so a slow live fetch
          // never blocks the guard cards below (which run off the persisted
          // account, not this snapshot). `status.account` is the selected account
          // and is non-null here (a null status returned early above).
          LiveAccountCard(accountId: status.account.id),
          const SizedBox(height: 16),
          DailyLossCard(status: status),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: MetricCard(
                  label: 'DRAWDOWN DISTANCE',
                  value: Formatters.money(status.drawdownDistance),
                  sub: 'limit ${Formatters.money(status.maxDrawdown)}',
                  accent: status.drawdownDistance < status.maxDrawdown * 0.25
                      ? AppColors.danger
                      : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  label: 'TO TARGET',
                  value: Formatters.pct(status.targetLeftPct),
                  sub: 'left',
                  accent: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TodayCard(status: status),
          const SizedBox(height: 16),
          EquitySparkCard(status: status),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _confirmStop(context, status),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.pan_tool_alt),
            label: const Text('STOP — Close all positions'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmStop(BuildContext context, GuardStatus status) async {
    // Coarse, non-PII: the trader reached for the emergency stop. No account
    // id, equity or drawdown value is attached.
    TelemetryService.instance.logEvent('guard_stop_pressed');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Close all positions?'),
        content: Text(
          'This is the equity guard. It requests a close-all on '
          '${status.account.nickname}. Live execution requires explicit consent and '
          'is disabled in paper mode.',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text(
              'Confirm',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Close-all requested (paper mode — nothing was sent).'),
        ),
      );
    }
  }
}

/// A full-screen Guard message for the empty and error states.
///
/// Deliberately distinct from the loading spinner: a failure to reach the backend and a
/// genuine "no accounts yet" are different things, and neither should look like the app is
/// still working. [onRetry], when supplied, adds a Retry action so a transient network
/// failure can be recovered in place.
class _GuardMessage extends StatelessWidget {
  const _GuardMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 36, color: AppColors.warning),
            const SizedBox(height: 12),
            Text(
              title,
              style: AppTextStyles.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: AppTextStyles.muted,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
