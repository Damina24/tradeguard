import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/auth_provider.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/disclaimer_note.dart';
import '../domain/delete_account.dart';

/// Two-step destructive confirmation for in-app account deletion (store compliance:
/// Apple 5.1.1(v), Google Play account-deletion).
///
/// Step 1 is the dialog itself; step 2 is the acknowledgement checkbox — the Delete button stays
/// disabled until it is checked, so a deletion can never be triggered by a single stray tap. The
/// copy states plainly that the action is irreversible and that an active subscription must be
/// cancelled manually in the App Store / Google Play (deleting the account does not stop billing).
///
/// The dialog never performs the deletion itself: it asks [deleteAccountRepositoryProvider], which
/// talks to the `delete-account` Edge Function. On success it signs out — the router's auth
/// redirect then routes to `/auth` — and shows a confirmation. On failure it shows a trader-safe
/// message from [DeleteAccountFailure]; a raw server error is never surfaced.
class DeleteAccountDialog extends ConsumerStatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  ConsumerState<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog> {
  /// Step 2 of the confirmation. Gates the Delete button.
  bool _acknowledged = false;

  /// True while the deletion request is in flight; disables both actions.
  bool _busy = false;

  /// A trader-safe failure message, shown inline. Never raw server text.
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    // Capture these before any await: a successful sign-out changes auth state and the router
    // redirect unmounts this dialog, after which `context` must not be touched.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    try {
      await ref.read(deleteAccountRepositoryProvider).deleteAccount();
    } on DeleteAccountException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.failure.message;
        });
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = DeleteAccountFailure.server.message;
        });
      }
      return;
    }

    // Success: clear the session. The router's auth redirect routes to `/auth` once the user is
    // null, so no explicit navigation is needed here.
    await ref.read(authProvider.notifier).signOut();
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Your account and data have been deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canConfirm = _acknowledged && !_busy;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Delete account?', style: AppTextStyles.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'This permanently deletes your TradeGuard account and everything in it — your '
              'profile, broker connections, trades, equity history, signal follows, AI reviews '
              'and uploaded screenshots. This cannot be undone.',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 12),
            Text(
              'Deleting your account does NOT cancel an active subscription. To stop billing, '
              'cancel it manually in the App Store or Google Play subscription settings.',
              style: AppTextStyles.body.copyWith(color: AppColors.warning),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _acknowledged,
              onChanged: _busy
                  ? null
                  : (bool? v) => setState(() => _acknowledged = v ?? false),
              activeColor: AppColors.danger,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'I understand this is permanent and cannot be undone.',
                style: AppTextStyles.body,
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error!, style: AppTextStyles.body.copyWith(color: AppColors.danger)),
            ],
            const SizedBox(height: 8),
            const DisclaimerNote(),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: canConfirm ? _confirm : null,
          child: Text(
            _busy ? 'Deleting…' : 'Delete',
            style: TextStyle(color: canConfirm ? AppColors.danger : AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}
