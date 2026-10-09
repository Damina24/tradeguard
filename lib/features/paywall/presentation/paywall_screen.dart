import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/services/providers.dart';
import '../../../core/services/telemetry_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/purchase_repository.dart';

/// TradeGuard Pro paywall (task 4.1b).
///
/// Reads [purchasesProvider] and renders exactly one of three states:
///
///   * **loading** — a spinner while the store offerings are fetched;
///   * **Pro**     — a confirmation with a checkmark and no purchase UI;
///   * **offers**  — the store packages (Monthly / Annual / …) with a Subscribe
///                   button each, a Restore Purchases action, and the verbatim
///                   risk disclaimer (a paywall is a compliance surface).
///
/// Every price comes from the store object itself (its localized `priceString`),
/// so the screen never invents a number. Purchases and restores are routed
/// through the notifier, which delegates to `Services.instance.purchases` and
/// records any failure on [PurchaseState.error]; this screen listens for that
/// error and surfaces it as a trader-safe SnackBar.
///
/// The Equity Guard, Kill Switch and STOP button are deliberately NOT part of
/// this paywall — they are safety features and stay free for every trader.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  @override
  void initState() {
    super.initState();
    // Coarse, non-PII: the paywall was opened. No user id, chosen plan or
    // price is attached — only the fact that the surface was viewed.
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
            ..showSnackBar(SnackBar(content: Text(_safeError(error))));
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
                : _Offers(state: state),
      ),
    );
  }
}

/// Maps any thrown object onto a short, trader-safe sentence. A raw SDK or
/// platform error never reaches the screen.
String _safeError(Object error) =>
    error is PurchaseFailure ? error.message : _Strings.genericError;

/// The offers list. A [ConsumerWidget] so each Subscribe / Restore control can
/// reach the notifier without threading `ref` through every widget.
class _Offers extends ConsumerWidget {
  const _Offers({required this.state});

  final PurchaseState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        _hero(),
        const SizedBox(height: 20),
        if (state.packages.isEmpty)
          const Text(_Strings.noOffers, style: AppTextStyles.muted)
        else
          for (final Object raw in state.packages)
            _packageCard(context, ref, raw),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => ref.read(purchasesProvider.notifier).restore(),
            child: const Text(_Strings.restore),
          ),
        ),
        const SizedBox(height: 20),
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
          ],
        ),
      );

  Widget _packageCard(BuildContext context, WidgetRef ref, Object raw) {
    final (String label, String price, String product) = _packageInfo(raw);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      // A Column, not a Row: the themed ElevatedButton carries an infinite
      // minimum width (Size.fromHeight), which is legal as a full-width child
      // here but illegal inside a horizontal Row.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label, style: AppTextStyles.title),
                    if (product.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(product, style: AppTextStyles.muted),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(price, style: AppTextStyles.metric),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              // Routed through the notifier so a failure lands in state.error
              // and is surfaced as a SnackBar; the notifier delegates to
              // Services.instance.purchases.purchase(package).
              onPressed: () =>
                  ref.read(purchasesProvider.notifier).purchase(raw),
              child: const Text(_Strings.subscribe),
            ),
          ),
        ],
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

/// Reads a store package into display fields. `priceString` is the store's own
/// localized price, so the screen never formats currency itself.
(String, String, String) _packageInfo(Object raw) {
  if (raw is Package) {
    return (
      _planLabel(raw.packageType),
      raw.storeProduct.priceString,
      raw.storeProduct.title,
    );
  }
  return (_Strings.planFallback, '', '');
}

/// A human label for a store package type.
String _planLabel(PackageType type) => switch (type) {
      PackageType.monthly => 'Monthly',
      PackageType.annual => 'Annual',
      PackageType.weekly => 'Weekly',
      PackageType.twoMonth => '2 months',
      PackageType.threeMonth => '3 months',
      PackageType.sixMonth => '6 months',
      PackageType.lifetime => 'Lifetime',
      PackageType.custom || PackageType.unknown => _Strings.planFallback,
    };

/// Paywall copy, kept out of the widget tree so no long string is inlined.
class _Strings {
  _Strings._();

  static const String title = 'TradeGuard Pro';
  static const String heroTitle = 'Unlock every premium tool';
  static const String heroBody =
      'AI chart analysis, AI trade reviews and copy-trading. The Equity Guard, '
      'Kill Switch and STOP button stay free for every trader.';
  static const String noOffers =
      'No subscription options are available right now. Please try again later.';
  static const String subscribe = 'Subscribe';
  static const String restore = 'Restore Purchases';
  static const String genericError = 'Something went wrong. Please try again.';
  static const String planFallback = 'Plan';
  static const String proMemberTitle = 'You are a Pro member';
  static const String proMemberBody =
      'Every premium tool is unlocked. Thanks for supporting TradeGuard.';
}
