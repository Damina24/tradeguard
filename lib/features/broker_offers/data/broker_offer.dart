/// A partner broker affiliate offer shown on the Broker Offers & Cashback screen.
///
/// Immutable value type: the whole catalogue is a compile-time `const` list, so
/// [BrokerOffer] has a `const` constructor and only final fields.
class BrokerOffer {
  const BrokerOffer({
    required this.id,
    required this.name,
    required this.affiliateUrl,
    required this.description,
    this.logoUrl,
  });

  /// Stable identifier for the offer (used as a list key / analytics id).
  final String id;

  /// Human-facing broker name, e.g. `FTMO`.
  final String name;

  /// Optional remote logo. Null when a partner has not supplied one; the list
  /// falls back to the first letter of [name].
  final String? logoUrl;

  /// The affiliate / referral URL opened inside the in-app WebView.
  final String affiliateUrl;

  /// Short, factual, compliance-safe blurb (no profit or win-rate promises).
  final String description;
}

/// Static catalogue of placeholder partner offers.
///
/// These are dummy `example.com` URLs until real affiliate links are supplied
/// (see Phase 4 in `docs/IMPLEMENTATION_PLAN.md`). Keeping them in one place
/// means the list screen and its tests read the same source of truth.
class BrokerOffers {
  BrokerOffers._();

  static const List<BrokerOffer> all = <BrokerOffer>[
    BrokerOffer(
      id: 'ftmo',
      name: 'FTMO',
      affiliateUrl: 'https://example.com/signup?ref=tradeguard&broker=ftmo',
      description: 'Prop firm funding programmes and trading evaluations.',
    ),
    BrokerOffer(
      id: 'topstep',
      name: 'Topstep',
      affiliateUrl: 'https://example.com/signup?ref=tradeguard&broker=topstep',
      description: 'Futures funding with performance-based accounts.',
    ),
    BrokerOffer(
      id: 'oanda',
      name: 'OANDA',
      affiliateUrl: 'https://example.com/signup?ref=tradeguard&broker=oanda',
      description: 'Forex and CFD broker with trading rebates.',
    ),
  ];
}
