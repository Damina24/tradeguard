import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// The non-happy states of the replay screen.
///
/// One widget for all of them, because the reason they are a single widget is the point: "still
/// loading", "nothing cached for this symbol", "too few bars to say anything", "the read failed" and
/// "the demo data is synthetic" must all be visibly different. An earlier draft of the sibling
/// patterns screen collapsed the middle ones into one grey box, which told a brand-new trader they
/// had no patterns when they actually had no data — the mistake [ReplayBarsStatus] exists to prevent.
class ReplayStateView extends StatelessWidget {
  const ReplayStateView({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.color = AppColors.textMuted,
    this.badge,
    super.key,
  });

  const ReplayStateView.loading({super.key})
      : icon = Icons.hourglass_empty,
        title = 'Loading price history',
        message = 'Reading the cached bars for this symbol.',
        actionLabel = null,
        onAction = null,
        color = AppColors.textMuted,
        badge = null;

  /// The read failed. Copy is generic on purpose — a PostgREST or Edge Function error can name
  /// tables, columns and constraints, none of which helps a trader and some of which must not be
  /// rendered.
  const ReplayStateView.error({
    required this.message,
    VoidCallback? onRetry,
    super.key,
  })  : icon = Icons.cloud_off,
        title = 'Could not load price history',
        actionLabel = 'Retry',
        onAction = onRetry,
        color = AppColors.warning,
        badge = null;

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color color;

  /// An optional chip, used for the `SYNTHETIC DEMO` provenance label.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final bool spinner = title == 'Loading price history';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (spinner)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 36, color: color),
          const SizedBox(height: 12),
          Text(title, style: AppTextStyles.title, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(message, style: AppTextStyles.muted, textAlign: TextAlign.center),
          if (badge != null) ...<Widget>[
            const SizedBox(height: 12),
            badge!,
          ],
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// The `SYNTHETIC DEMO` chip.
///
/// Unmissable on purpose. A generated chart shown without it is indistinguishable from a market chart,
/// and for a backtest that is the single most misleading thing this product could ship.
class SyntheticDemoChip extends StatelessWidget {
  const SyntheticDemoChip({this.label = 'SYNTHETIC DEMO', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accent),
      ),
      child: Text(
        label,
        style: AppTextStyles.label.copyWith(color: AppColors.accent),
      ),
    );
  }
}