import 'package:flutter/material.dart';

import '../../../core/models/guard_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';

class StateBanner extends StatelessWidget {
  const StateBanner({required this.status, super.key});

  final GuardStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status.state) {
      GuardState.ok => (AppColors.primary, Icons.verified_user),
      GuardState.warn => (AppColors.warning, Icons.warning_amber),
      GuardState.critical => (AppColors.danger, Icons.error_outline),
      GuardState.breach => (AppColors.danger, Icons.gpp_bad),
      GuardState.stale => (AppColors.warning, Icons.history),
      GuardState.error => (AppColors.textMuted, Icons.cloud_off),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${status.state.label}  •  ${status.account.platform.toUpperCase()}'
              '  •  updated ${Formatters.timeAgo(status.asOf)}',
              style: AppTextStyles.muted.copyWith(color: color),
            ),
          ),
          const SizedBox(width: 8),
          // A separate connection indicator, independent of the guard-risk colour
          // above. GREEN only when the account has a live broker link and the
          // snapshot is fresh; grey when there is no link; amber while it is
          // merely stale. Red is reserved for a genuine offline/error link, which
          // the guard state already reflects — so a healthy, connected account is
          // never painted red here.
          _ConnectionDot(status: status),
        ],
      ),
    );
  }
}

/// The connection half of the banner: a dot + label that reports link health on
/// its own, so it cannot be mistaken for (or overridden by) the risk colour.
class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.status});

  final GuardStatus status;

  @override
  Widget build(BuildContext context) {
    final String? link = status.account.metaapiAccountId;
    final bool hasLink = link != null && link.isNotEmpty;

    final Color color;
    final String label;
    if (!hasLink) {
      color = AppColors.textMuted;
      label = 'NOT LINKED';
    } else if (status.isStale) {
      // A link that exists but whose snapshot is old is still a live link — it is
      // waiting on the next sync, not broken. Amber, never red.
      color = AppColors.warning;
      label = 'SYNCING';
    } else {
      color = AppColors.primary; // the app's success/green
      label = 'CONNECTED';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.label.copyWith(color: color)),
      ],
    );
  }
}

