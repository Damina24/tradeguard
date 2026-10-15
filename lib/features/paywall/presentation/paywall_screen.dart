import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/services/providers.dart';
import '../../../core/services/telemetry_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// TradeGuard Pro paywall — Flutterwave Payment Link flow.
///
/// The simplest possible flow: no store SDK, no subscription table, just a
/// boolean. The trader picks a tier, taps **Subscribe** and the Flutterwave
/// Payment Link opens in the device browser. Flutterwave charges the card and
/// calls the `flutterwave-webhook` Edge Function, which flips
/// `profiles.is_premium` to true. The trader returns, taps
/// **I Have Subscribed / Check Status**, and this screen re-reads that flag:
/// on success it shows a confirmation, closes the paywall and the rest of the
/// app unlocks (every Pro gate reads [purchasesProvider].isPro).
///
/// Three states, read from [purchasesProvider]:
///   * **loading** — a spinner while the flag is (re)read;
///   * **Pro**     — a confirmation with a checkmark and no purchase UI;
///   * **offers**  — the tier picker + Subscribe + Check Status actions and
///                   the verbatim risk disclaimer (a paywall is a compliance
///                   surface).
///
/// The Equity Guard, Kill Switch and STOP button are deliberately NOT part of
/// this paywall — they are safety features and stay free for every trader.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  static const String monthlyUrl = 'https://flutterwave.com/pay/ejczulfxgvxf';
  static const String quarterlyUrl = 'https://flutterwave.com/pay/z7r9rp6andzq';
  static const String yearlyUrl = 'https://flutterwave.com/pay/ekkpn45pipap';

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

/// The three Flutterwave billing tiers.
enum PaywallTier { monthly, quarterly, yearly }

extension PaywallTierX on PaywallTier {
  /// The Flutterwave Payment Link for this tier.
  String get url {
    switch (this) {
      case PaywallTier.monthly:
        return PaywallScreen.monthlyUrl;
      case PaywallTier.quarterly:
        return PaywallScreen.quarterlyUrl;
      case PaywallTier.yearly:
        return PaywallScreen.yearlyUrl;
    }
  }

  /// Short title shown on the selectable card.
  String get title {
    switch (this) {
      case PaywallTier.monthly:
        return 'Monthly';
      case PaywallTier.quarterly:
        return 'Quarterly';
      case PaywallTier.yearly:
        return 'Yearly';
    }
  }

  /// Price line shown on the selectable card (USD only).
  String get priceLine {
    switch (this) {
      case PaywallTier.monthly:
        return r'$14.99 / month';
      case PaywallTier.quarterly:
        return r'$39.99 / 3 months';
      case PaywallTier.yearly:
        return r'$144.99 / year';
    }
  }

  /// Subscribe button label for this tier (USD only).
  String get subscribeLabel {
    switch (this) {
      case PaywallTier.monthly:
        return r'Subscribe for $14.99 / month';
      case PaywallTier.quarterly:
        return r'Subscribe for $39.99 / 3 months';
      case PaywallTier.yearly:
        return r'Subscribe for $144.99 / year';
    }
  }
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  /// True while a "Check Status" tap is re-reading the flag, so the button can
  /// show its own busy state separate from the initial load.
  bool _checking = false;

  /// Currently selected billing tier. Defaults to monthly.
  PaywallTier _selected = PaywallTier.monthly;

  @override
  void initState() {
    super.initState();
    // Coarse, non-PII: the paywall was opened. No user id, plan or price is
    // attached — only the fact that the surface was viewed.
    TelemetryService.instance.logEvent('paywall_viewed');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PurchaseState>(
      purchasesProvider,
      (PurchaseState? previous, PurchaseState next) {
        final Object? error = next.error;
        if (error != null && !identical(error, previous?.error)) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text(_Strings.genericError)),
            );
        }
      },
    );

    final PurchaseState state = ref.watch(purchasesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(_Strings.title)),
      body: SafeArea(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : state.isPro
                ? const _ProMember()
                : _Offers(
                    selected: _selected,
                    onSelect: (PaywallTier tier) =>
                        setState(() => _selected = tier),
                    checking: _checking,
                    onSubscribe: _subscribe,
                    onCheckStatus: _checkStatus,
                  ),
      ),
    );
  }

  /// Opens the Flutterwave Payment Link for the currently selected tier in the
  /// device's external browser. A failure to launch (no browser, or the
  /// launcher threw) is reported rather than swallowed, so the tap never
  /// silently does nothing. The URL is a public payment link, not a secret;
  /// nothing sensitive is logged.
  Future<void> _subscribe() async {
    final Uri uri = Uri.parse(_selected.url);
    try {
      final bool launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _snack(_Strings.openFailed);
      }
    } catch (_) {
      if (mounted) _snack(_Strings.openFailed);
    }
  }

  /// Re-reads `profiles.is_premium`. On success it shows a confirmation and
  /// pops the paywall so the app is already unlocked underneath; otherwise it
  /// tells the trader the payment has not been seen yet. Never a raw error.
  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    try {
      await ref.read(purchasesProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    if (!mounted) return;

    final bool isPro = ref.read(purchasesProvider).isPro;
    if (isPro) {
      _snack(_Strings.activated);
      // Close the paywall: presented as a pushed route (Settings) or a modal
      // sheet (Signals / AI Review / Copy). `maybeOf` + `canPop` covers both
      // and is a no-op when there is nothing to pop.
      final NavigatorState? nav = Navigator.maybeOf(context);
      if (nav != null && nav.canPop()) nav.pop();
    } else {
      _snack(_Strings.notYet);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The offers list: hero, tier picker, the two actions, and the verbatim risk
/// disclaimer.
class _Offers extends StatelessWidget {
  const _Offers({
    required this.selected,
    required this.onSelect,
    required this.checking,
    required this.onSubscribe,
    required this.onCheckStatus,
  });

  final PaywallTier selected;
  final ValueChanged<PaywallTier> onSelect;
  final bool checking;
  final VoidCallback onSubscribe;
  final VoidCallback onCheckStatus;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        _hero(),
        const SizedBox(height: 20),
        // Tier picker: three selectable cards bound to the state-owned tier.
        for (final PaywallTier tier in PaywallTier.values) ...<Widget>[
          _TierCard(
            tier: tier,
            selected: tier == selected,
            onTap: () => onSelect(tier),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        // The primary action: open the Flutterwave Payment Link for the
        // selected tier in the browser.
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onSubscribe,
            child: Text(selected.subscribeLabel),
          ),
        ),
        const SizedBox(height: 12),
        // After paying, the trader comes back and taps this to re-read the
        // flag the webhook set.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: checking ? null : onCheckStatus,
            child: checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(_Strings.checkStatus),
          ),
        ),
        const SizedBox(height: 20),
        // Compliance: a paywall is a risk surface, so the disclaimer is always
        // shown (AGENTS.md).
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: const Text(
            AppStrings.riskDisclaimer,
            style: AppTextStyles.disclaimer,
          ),
        ),
      ],
    );
  }

  Widget _hero() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(_Strings.heroTitle, style: AppTextStyles.h2),
            SizedBox(height: 6),
            Text(_Strings.heroBody, style: AppTextStyles.muted),
            SizedBox(height: 12),
            Text(_Strings.priceHint, style: AppTextStyles.metric),
          ],
        ),
      );
}

/// One selectable billing tier: a card with a radio indicator, the tier title
/// and the USD price line.
class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.selected,
    required this.onTap,
  });

  final PaywallTier tier;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color border = selected ? AppColors.primary : AppColors.divider;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: selected ? 2 : 1),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              // ignore: avoid_bool_literals_in_conditional_expressions
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(tier.title, style: AppTextStyles.h2),
                  const SizedBox(height: 2),
                  Text(tier.priceLine, style: AppTextStyles.muted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Pro confirmation. No purchase UI — a member has nothing to buy.
class _ProMember extends StatelessWidget {
  const _ProMember();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.check_circle, color: AppColors.primary, size: 56),
            SizedBox(height: 16),
            Text(
              _Strings.proMemberTitle,
              style: AppTextStyles.h2,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              _Strings.proMemberBody,
              style: AppTextStyles.muted,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Paywall copy, kept out of the widget tree so no long string is inlined.
class _Strings {
  _Strings._();

  static const String title = 'TradeGuard Pro';
  static const String heroTitle = 'Unlock every premium tool';
  static const String heroBody =
      'AI chart analysis, AI trade reviews and copy-trading. The Equity Guard, '
      'Kill Switch and STOP button stay free for every trader.';
  static const String priceHint = r'From $14.99 / month — pick a plan below';
  static const String checkStatus = 'I Have Subscribed / Check Status';
  static const String activated = 'Subscription active — welcome to Pro!';
  static const String notYet =
      'We could not find your subscription yet. If you have just paid, wait a '
      'moment and tap Check Status again.';
  static const String openFailed = 'Could not open the payment page.';
  static const String genericError = 'Something went wrong. Please try again.';
  static const String proMemberTitle = 'You are a Pro member';
  static const String proMemberBody =
      'Every premium tool is unlocked. Thanks for supporting TradeGuard.';
}
