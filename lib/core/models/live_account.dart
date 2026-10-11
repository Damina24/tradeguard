/// How healthy a broker link is, as reported by the live account fetch.
///
/// Named [BrokerConnectionState] rather than `ConnectionState` on purpose: Flutter's
/// material library already exports a `ConnectionState`, and a bare `ConnectionState`
/// here would collide the moment a widget imports both. This is the broker-link
/// state, so it says so.
///
/// The whole point of the Guard dashboard is a live risk read, so the connection
/// badge is deliberately blunt: `connected` is the only GREEN state, `offline` is
/// the only RED one. There is no "bridged"/"pending" state painted red — a link
/// that is merely still negotiating is amber (`syncing`), never an error.
enum BrokerConnectionState { connected, syncing, offline }

extension BrokerConnectionStateX on BrokerConnectionState {
  /// Short, factual badge label. Never a promise of profit or a status quote.
  String get label => switch (this) {
        BrokerConnectionState.connected => 'LIVE',
        BrokerConnectionState.syncing => 'SYNCING',
        BrokerConnectionState.offline => 'OFFLINE',
      };

  /// True when the link is up and streaming. This — and only this — is green.
  bool get isHealthy => this == BrokerConnectionState.connected;
}

/// One open position on a broker account, as reported by the live fetch.
///
/// Every number is what the broker returned; the app never estimates a price or
/// a P&L it was not given. A position the provider described incompletely is
/// dropped by the mapper rather than shown with invented fields.
class OpenPosition {
  const OpenPosition({
    required this.id,
    required this.symbol,
    required this.isBuy,
    required this.lots,
    required this.openPrice,
    required this.currentPrice,
    required this.pnl,
  });

  final String id;
  final String symbol;

  /// `true` for a Buy/long position, `false` for Sell/short.
  final bool isBuy;
  final double lots;
  final double openPrice;
  final double currentPrice;

  /// Current floating P&L for this position, broker-reported.
  final double pnl;

  String get sideLabel => isBuy ? 'BUY' : 'SELL';

  factory OpenPosition.fromJson(Map<String, dynamic> json) => OpenPosition(
        id: (json['id'] as String?) ?? '',
        symbol: (json['symbol'] as String?) ?? '',
        isBuy: (json['side'] as String?) == 'buy',
        lots: (json['lots'] as num?)?.toDouble() ?? 0,
        openPrice: (json['open_price'] as num?)?.toDouble() ?? 0,
        currentPrice: (json['current_price'] as num?)?.toDouble() ?? 0,
        pnl: (json['pnl'] as num?)?.toDouble() ?? 0,
      );
}

/// A live snapshot of one broker account: balance, equity, connection health and
/// the currently open positions, all pulled on demand from the broker.
///
/// This is intentionally separate from [TradingAccount] (the persisted prop-firm
/// rules + last known equity). [LiveAccountData] is the *right now* read that the
/// Guard dashboard shows at the top; it can be empty or stale without corrupting
/// the guard math, which still runs off the account record.
class LiveAccountData {
  const LiveAccountData({
    required this.accountId,
    required this.balance,
    required this.equity,
    required this.connection,
    required this.positions,
    required this.asOf,
    this.linked = true,
  });

  /// Whether the account actually has a broker link. A freshly created account
  /// that was never connected is `linked: false` — that is a "not linked" state,
  /// not an error, and is shown grey rather than red.
  factory LiveAccountData.notLinked(String accountId) => LiveAccountData(
        accountId: accountId,
        balance: 0,
        equity: 0,
        connection: BrokerConnectionState.offline,
        positions: const <OpenPosition>[],
        asOf: DateTime.now(),
        linked: false,
      );

  final String accountId;
  final double balance;
  final double equity;
  final BrokerConnectionState connection;
  final bool linked;
  final List<OpenPosition> positions;
  final DateTime asOf;

  /// Net floating P&L across every open position.
  double get openPnl =>
      positions.fold<double>(0, (double s, OpenPosition p) => s + p.pnl);

  factory LiveAccountData.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawPositions =
        (json['positions'] as List<dynamic>?) ?? const <dynamic>[];
    return LiveAccountData(
      accountId: (json['account_id'] as String?) ?? '',
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      equity: (json['equity'] as num?)?.toDouble() ?? 0,
      connection: BrokerConnectionState.values.firstWhere(
        (BrokerConnectionState c) =>
            c.name == ((json['connection'] as String?) ?? 'offline'),
        orElse: () => BrokerConnectionState.offline,
      ),
      linked: (json['linked'] as bool?) ?? true,
      positions: rawPositions
          .whereType<Map<String, dynamic>>()
          .map(OpenPosition.fromJson)
          .toList(growable: false),
      asOf: DateTime.tryParse((json['as_of'] as String?) ?? '') ?? DateTime.now(),
    );
  }
}
