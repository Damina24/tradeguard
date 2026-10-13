import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/services/providers.dart';
import '../../../core/services/telemetry_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// TradeGuard Pro paywall — Paystack Payment Page flow.
///
/// The simplest possible flow: no store SDK, no subscription table, just a
/// boolean. The trader taps **Subscribe** and the Paystack Payment Page opens
/// in the device browser. Paystack charges the card and calls the
/// `paystack-webhook` Edge Function, which flips `profiles.is_premium` to true.
/// The trader returns, taps **I Have Subscribed / Check Status**, and this
/// screen re-reads that flag: on success it shows a confirmation, closes the
/// paywall and the rest of the app unlocks (every Pro gate reads
/// [purchasesProvider].isPro).
///
/// Three states, read from [purchasesProvider]:
///   * **loading** — a spinner while the flag is (re)read;
///   * **Pro**     — a confirmation with a checkmark and no purchase UI;
///   * **offers**  — the Subscribe + Check Status actions and the verbatim risk
///                   disclaimer (a paywall is a compliance surface).
///
/// The Equity Guard, Kill Switch and STOP button are deliberately NOT part of
/// this paywall — they are safety features and stay free for every trader.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  /// True while a "Check Status" tap is re-reading the flag, so the button can
  /// show its own busy state separate from the initial load.
  bool _checking = false;

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
                    checking: _checking,
                    onSubscribe: _subscribe,
                    onCheckStatus: _checkStatus,
                  ),
      ),
    );
  }

  /// Opens the Paystack Payment Page in the device's external browser. A failure
  /// to launch (no browser, or the launcher threw) is reported rather than
  /// swallowed, so the tap never silently does nothing. The URL is a public
  /// payment link, not a secret; nothing sensitive is logged.
  Future<void> _subscribe() async {
    final Uri uri = Uri.parse(_Strings.paystackUrl);
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

/// The offers list: hero, the two actions, and the verbatim risk disclaimer.
class _Offers extends StatelessWidget {
  const _Offers({
    required this.checking,
    required this.onSubscribe,
    required this.onCheckStatus,
  });

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
        // The primary action: open the Paystack Payment Page in the browser.
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onSubscribe,
            child: const Text(_Strings.subscribe),
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
            Text(_Strings.price, style: AppTextStyles.metric),
          ],
        ),
      );
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
  static const String price = '₦14,999 / month';
  static const String subscribe = 'Subscribe for ₦14,999/month';
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

  /// The Paystack Payment Page link. Replace the placeholder with the real
  /// payment page URL (Paystack Dashboard → Payment Pages) before release.
  static const String paystackUrl =
      'https://paystack.com/pay/YOUR_PAYMENT_PAGE_LINK_HERE';
}

