import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// The non-happy states of the pattern and leaks screens.
///
/// One widget for all of them, because the reason they are a single widget is the
/// point: "still loading", "you have no trades", "not enough trades yet" and
/// "the read failed" must be visibly different things. An earlier version of this
/// screen collapsed the middle two into one grey "nothing here" box, which told a
/// brand-new trader they had no patterns when they actually had no data — the
/// mistake [PatternStatus] exists to prevent.
class PatternStateView extends StatelessWidget {
  const PatternStateView({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.actionLabel,
    this.color = AppColors.textMuted,
    super.key,
  });

  /// The still-loading state: a spinner and no words, so nothing is claimed yet.
  const PatternStateView.loading({super.key})
      : icon = Icons.hourglass_empty,
        title = 'Loading patterns',
        message = 'Reading your trade history.',
        action = null,
        actionLabel = null,
        color = AppColors.textMuted;

  /// The repository failed. Copy is generic on purpose — a PostgREST exception can
  /// name tables, columns and constraints, none of which helps a trader and some of
  /// which must not be shown.
  const PatternStateView.error({VoidCallback? onRetry, super.key})
      : icon = Icons.cloud_off,
        title = 'Could not load your patterns',
        message = 'Check your connection and try again.',
        action = onRetry,
        actionLabel = 'Retry',
        color = AppColors.warning;

  final IconData icon;
  final String title;
  final String message;

  /// Retry handler, when there is something useful to retry.
  final VoidCallback? action;
  final String? actionLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bool spinner = title == 'Loading patterns';

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
          if (action != null && actionLabel != null) ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: action,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}