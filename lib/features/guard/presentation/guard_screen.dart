import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/account.dart';
import '../../../core/models/guard_status.dart';
import '../../../core/services/providers.dart';
import '../../../core/services/telemetry_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/account_chip.dart';
import '../widgets/daily_loss_card.dart';
import '../widgets/equity_spark_card.dart';
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
            onPressed: () => ref.invalidate(guardStatusProvider),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: status == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.surface,
              onRefresh: () async {
                await Future<void>.delayed(const Duration(milliseconds: 400));
                ref.invalidate(guardStatusProvider);
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
                  DailyLossCard(status: status),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: MetricCard(
                          label: 'DRAWDOWN DISTANCE',
                          value: Formatters.money(status.drawdownDistance),
                          sub: 'limit ${Formatters.money(status.maxDrawdown)}',
                          accent: status.drawdownDistance <
                                  status.maxDrawdown * 0.25
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
            child: const Text('Confirm', style: TextStyle(color: AppColors.danger)),
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
