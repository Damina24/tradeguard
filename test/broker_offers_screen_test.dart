import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/theme/app_theme.dart';
import 'package:tradeguard/features/broker_offers/data/broker_offer.dart';
import 'package:tradeguard/features/broker_offers/presentation/broker_offers_screen.dart';

void main() {
  testWidgets('renders every placeholder broker with its name and description',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const BrokerOffersScreen()),
    );
    await tester.pumpAndSettle();

    // The list is driven by BrokerOffers.all, so assert against that source of
    // truth rather than hard-coding names — the two must never drift apart.
    for (final BrokerOffer offer in BrokerOffers.all) {
      expect(find.text(offer.name), findsOneWidget);
      expect(find.text(offer.description), findsOneWidget);
    }

    // A couple of concrete anchors so the test fails loudly if the catalogue
    // is ever emptied by accident.
    expect(find.text('FTMO'), findsOneWidget);
    expect(find.text('Topstep'), findsOneWidget);

    // Compliance: the offers surface always shows the risk disclaimer.
    expect(find.textContaining('high-risk'), findsOneWidget);
  });
}
