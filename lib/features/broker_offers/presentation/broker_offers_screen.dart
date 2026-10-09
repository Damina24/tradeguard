import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/disclaimer_note.dart';
import '../data/broker_offer.dart';

/// Broker Offers & Cashback — the list of partner brokers whose signup / rebate
/// pages open in the in-app affiliate [BrokerWebViewScreen].
///
/// This is a monetisation surface, so it carries the shared risk disclaimer
/// (compliance guardrail in `AGENTS.md`). It never touches paywall, guard or
/// copy-trading logic: tapping a row only pushes the WebView route.
class BrokerOffersScreen extends StatelessWidget {
  const BrokerOffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Broker Offers & Cashback')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Open a funded or cashback account with a partner broker. '
              'Pages open in-app; use the browser button for KYC or banking steps.',
              style: AppTextStyles.muted,
            ),
          ),
          for (final BrokerOffer offer in BrokerOffers.all)
            _OfferTile(offer: offer),
          const SizedBox(height: 16),
          const DisclaimerNote(),
        ],
      ),
    );
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer});

  final BrokerOffer offer;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.surfaceAlt,
          child: Text(
            offer.name.substring(0, 1),
            style: AppTextStyles.label,
          ),
        ),
        title: Text(offer.name, style: AppTextStyles.body),
        subtitle: Text(offer.description, style: AppTextStyles.muted),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
        onTap: () => context.push(
          '/broker-webview'
          '?url=${Uri.encodeComponent(offer.affiliateUrl)}'
          '&title=${Uri.encodeComponent(offer.name)}',
        ),
      ),
    );
  }
}
