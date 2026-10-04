import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/account.dart';
import '../../../core/models/signal.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/trading_math.dart';

class CopyConfirmSheet extends StatefulWidget {
  const CopyConfirmSheet({required this.signal, super.key});

  final Signal signal;

  @override
  State<CopyConfirmSheet> createState() => _CopyConfirmSheetState();
}

class _CopyConfirmSheetState extends State<CopyConfirmSheet> {
  double _riskPct = 1.0;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? child) {
        final List<TradingAccount> accounts = ref.watch(accountsProvider);
        final TradingAccount? selected = ref.watch(selectedAccountProvider);
        if (accounts.isEmpty) {
          return const Center(child: Text('Connect a broker account first.'));
        }
        final TradingAccount account = accounts.firstWhere(
          (TradingAccount a) => a.id == selected?.id,
          orElse: () => accounts.first,
        );

        final double stopPips = TradingMath.pipsBetween(
          widget.signal.pair,
          widget.signal.entry,
          widget.signal.stop,
        );
        final double lots = TradingMath.lotSize(
          balance: account.equity,
          riskPct: _riskPct,
          symbol: widget.signal.pair,
          stopPips: stopPips,
        );
        final double riskAmount = account.equity * _riskPct / 100;
        final double rr = TradingMath.rewardRisk(
          entry: widget.signal.entry,
          stop: widget.signal.stop,
          target: widget.signal.tp1,
        );

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Text('Copy Signal', style: AppTextStyles.h2),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'PAPER MODE',
                      style: AppTextStyles.label.copyWith(color: AppColors.warning),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${widget.signal.pair} • '
                '${widget.signal.direction == SignalDirection.buy ? 'BUY' : 'SELL'}'
                ' • ${stopPips.toStringAsFixed(1)} pips SL • 1:${rr.toStringAsFixed(2)}',
                style: AppTextStyles.body,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: account.id,
                dropdownColor: AppColors.surfaceAlt,
                decoration: const InputDecoration(labelText: 'Account'),
                items: <DropdownMenuItem<String>>[
                  for (final TradingAccount a in accounts)
                    DropdownMenuItem<String>(
                      value: a.id,
                      child: Text(a.nickname),
                    ),
                ],
                onChanged: (String? v) =>
                    ref.read(selectedAccountIdProvider.notifier).state = v ?? account.id,
              ),
              const SizedBox(height: 16),
              Text('Risk: ${_riskPct.toStringAsFixed(2)}%', style: AppTextStyles.body),
              Slider(
                value: _riskPct,
                min: 0.25,
                max: 5,
                divisions: 19,
                activeColor: AppColors.primary,
                onChanged: (double v) => setState(() => _riskPct = v),
              ),
              _row('Position size', '${lots.toStringAsFixed(2)} lots'),
              _row('Max loss', Formatters.money(riskAmount)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Text(
                  'Trading forex/gold/CFDs is high-risk and you can lose all capital. '
                  'Copy-trading amplifies losses. Paper mode unless you enable live copy '
                  'with explicit consent. Not financial advice.',
                  style: AppTextStyles.disclaimer,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _confirm(context, lots),
                child: const Text('Confirm Copy'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirm(BuildContext context, double lots) {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Paper copy placed: ${lots.toStringAsFixed(2)} lots '
          '${widget.signal.pair} (nothing sent to a broker).',
        ),
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
