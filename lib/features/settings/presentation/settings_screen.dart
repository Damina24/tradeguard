import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/account.dart';
import '../../../core/services/auth_provider.dart';
import '../../../core/services/auth_repository.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/disclaimer_note.dart';
import '../../accounts/presentation/connect_broker_sheet.dart';
import '../../paywall/presentation/paywall_screen.dart';
import 'delete_account_dialog.dart';
import 'settings_tiles.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<TradingAccount> accounts = ref.watch(accountsProvider);
    final AppUser? user = ref.watch(authProvider);
    final bool isPro = ref.watch(purchasesProvider).isPro;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          SettingsTiles.profile(
            email: user?.email,
            isPro: isPro,
            onUpgrade: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PaywallScreen()),
            ),
          ),
          const SizedBox(height: 20),
          const Text('ACCOUNTS', style: AppTextStyles.label),
          const SizedBox(height: 8),
          for (final TradingAccount a in accounts)
            AccountRow(account: a),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _connect(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Connect broker (read-only)'),
          ),
          const SizedBox(height: 20),
          const Text('SUBSCRIPTION', style: AppTextStyles.label),
          const SizedBox(height: 8),
          SettingsTiles.tile(Icons.restore, 'Restore purchases',
              () => SettingsTiles.snack(context, 'No purchases found.'),),
          SettingsTiles.tile(
            Icons.card_giftcard,
            'Broker Offers & Cashback',
            () => context.push('/broker-offers'),
          ),
          const SizedBox(height: 20),
          const Text('LEGAL', style: AppTextStyles.label),
          const SizedBox(height: 8),
          SettingsTiles.tile(Icons.privacy_tip_outlined, 'Privacy policy',
              () => _open(context, AppConfig.privacyUrl),),
          SettingsTiles.tile(Icons.description_outlined, 'Terms of service',
              () => _open(context, AppConfig.termsUrl),),
          SettingsTiles.tile(
              Icons.warning_amber, 'Risk disclaimer', () => SettingsTiles.showDisclaimer(context),),
          const SizedBox(height: 16),
          const DisclaimerNote(),
          const SizedBox(height: 20),
          SettingsTiles.tile(Icons.logout, 'Sign out', () => _signOut(context, ref)),
          SettingsTiles.tile(
            Icons.delete_forever,
            'Delete account',
            () => showDialog<void>(
              context: context,
              builder: (BuildContext c) => const DeleteAccountDialog(),
            ),
            color: AppColors.danger,
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              '${AppStrings.storeTitle} v0.1.0 (Phase 0)',
              style: AppTextStyles.disclaimer,
            ),
          ),
        ],
      ),
    );
  }

  /// Opens a legal page in the external browser.
  ///
  /// Legal links used to be shown in a SnackBar that only printed the URL —
  /// a trader cannot tap raw text, so the page effectively never opened. This
  /// hands the URL to the platform browser (same pattern the auth screen uses).
  /// A failure to launch (no browser, or the launcher threw) is reported rather
  /// than swallowed, so the tap never silently does nothing.
  Future<void> _open(BuildContext context, String url) async {
    try {
      final bool launched =
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        SettingsTiles.snack(context, 'Could not open the link.');
      }
    } catch (_) {
      if (context.mounted) {
        SettingsTiles.snack(context, 'Could not open the link.');
      }
    }
  }

  /// Ends the session and returns to the auth screen.
  ///
  /// Clearing the session is the real work: [AuthNotifier.signOut] sets the user
  /// to null, which pings the router's refresh notifier, and `AppRouter.redirect`
  /// then sends the app to `/auth` on its own. The explicit `go` below covers the
  /// case where Settings is mounted without a router (a modal, or a widget test),
  /// where no redirect runs — there it is simply skipped, because the session has
  /// already been cleared and that is the part the trader can observe.
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(authProvider.notifier).signOut();
    if (!context.mounted) return;
    GoRouter.maybeOf(context)?.go('/auth');
  }

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // The sheet owns the password fields and clears them itself; this handler only reports the
    // outcome, so nothing credential-shaped ever passes back through here.
    final bool connected = await showConnectBrokerSheet(context);
    if (!connected) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Broker connected. Guard will refresh shortly.')),
      );
  }
}

/// One connected broker account: identity, live/stubbed state, and the two destructive-ish
/// actions (equity guard toggle, remove). Business logic stays in [AccountsNotifier].
class AccountRow extends ConsumerWidget {
  const AccountRow({required this.account, super.key});

  final TradingAccount account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.account_balance, color: AppColors.accent),
        title: Text(account.nickname, style: AppTextStyles.body),
        subtitle: Text(
          '${account.platform.toUpperCase()} • ${account.phase.name.toUpperCase()} • '
          '${account.propFirm ?? 'Personal'}'
          '${account.metaapiAccountId == null ? ' • not linked' : ''}',
          style: AppTextStyles.muted,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: account.equityGuardEnabled
                  ? 'Disable equity guard'
                  : 'Enable equity guard',
              icon: Icon(
                account.equityGuardEnabled
                    ? Icons.shield
                    : Icons.shield_outlined,
                color: account.equityGuardEnabled
                    ? AppColors.primary
                    : AppColors.textMuted,
              ),
              onPressed: () => ref
                  .read(accountsProvider.notifier)
                  .setEquityGuardEnabled(account.id, !account.equityGuardEnabled),
            ),
            IconButton(
              tooltip: 'Remove account',
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: () => _confirmRemove(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Remove ${account.nickname}?'),
        content: const Text(
          'This removes the account, its trades and its equity history from TradeGuard. '
          'The connection at your broker is not changed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(accountsProvider.notifier).removeAccount(account.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${account.nickname} removed.')));
  }
}

