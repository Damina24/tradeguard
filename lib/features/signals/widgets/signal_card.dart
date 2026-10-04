import 'package:flutter/material.dart';

import '../../../core/models/signal.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';

class SignalCard extends StatelessWidget {
  const SignalCard({required this.signal, required this.onCopy, super.key});

  final Signal signal;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final bool isBuy = signal.direction == SignalDirection.buy;
    final Color dirColor = isBuy ? AppColors.primary : AppColors.danger;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              Text(signal.pair, style: AppTextStyles.h2),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: dirColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isBuy ? 'BUY' : 'SELL',
                  style: AppTextStyles.label.copyWith(color: dirColor),
                ),
              ),
              if (signal.premium) ...<Widget>[
                const SizedBox(width: 6),
                const Icon(Icons.workspace_premium, size: 16, color: AppColors.warning),
              ],
              const Spacer(),
              Text(
                Formatters.timeAgo(signal.createdAt),
                style: AppTextStyles.muted,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _level('Entry', signal.entry, AppColors.textPrimary),
              _level('SL', signal.stop, AppColors.danger),
              _level('TP1', signal.tp1, AppColors.primary),
              if (signal.tp2 != null) _level('TP2', signal.tp2!, AppColors.primary),
            ],
          ),
          const SizedBox(height: 12),
          Text(signal.rationale, style: AppTextStyles.muted),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('CONFIDENCE', style: AppTextStyles.label),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: signal.confidence / 100,
                        minHeight: 8,
                        backgroundColor: AppColors.surfaceAlt,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (signal.status == SignalStatus.active)
                ElevatedButton.icon(
                  onPressed: onCopy,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(96, 44),
                    backgroundColor: AppColors.primary,
                  ),
                  icon: const Icon(Icons.content_copy, size: 16),
                  label: const Text('Copy'),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    signal.resultPips == null
                        ? 'CLOSED'
                        : '${signal.resultPips! >= 0 ? '+' : ''}'
                            '${signal.resultPips!.toStringAsFixed(0)} pips',
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.forPnl(signal.resultPips ?? 0),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _level(String label, double value, Color color) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: AppTextStyles.label),
            const SizedBox(height: 2),
            Text(
              value.toStringAsFixed(value >= 100 ? 2 : 4),
              style: AppTextStyles.body.copyWith(color: color),
            ),
          ],
        ),
      );
}
