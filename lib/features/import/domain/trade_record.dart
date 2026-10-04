import '../../../core/models/trade.dart';

/// Canonical, broker-agnostic trade row produced by every importer.
///
/// This is deliberately NOT a copy of any broker's statement format. Parsers map their own
/// column names onto these fields (see `FieldAliasTable`) and nothing downstream — validation,
/// the repository, or the UI — ever sees a raw CSV column or an HTML node.
///
/// It carries exactly what the journal already needs ([toTrade] produces the existing
/// [Trade]) plus the execution detail the `trades` table can store: costs ([commission],
/// [swap]) and provenance ([externalId], [broker], [accountNumber], [currency]).
class TradeRecord {
  const TradeRecord({
    required this.externalId,
    required this.symbol,
    required this.direction,
    required this.volumeLots,
    required this.profit,
    this.commission = 0,
    this.swap = 0,
    this.entryPrice,
    this.exitPrice,
    this.stopLoss,
    this.takeProfit,
    this.openTime,
    this.closeTime,
    this.broker,
    this.accountNumber,
    this.currency,
  });

  /// Broker order/deal/position identifier. The duplicate-detection key.
  final String externalId;

  /// Normalized instrument, e.g. `XAUUSD`. See `ValueNormalizer.symbol`.
  final String symbol;

  final TradeDirection direction;

  /// Size in lots. Always > 0 — validation rejects zero, negative and absurd values.
  final double volumeLots;

  /// Gross profit/loss as reported by the broker, excluding costs.
  final double profit;

  /// Commission. Brokers report it as a negative number; it is summed, not subtracted, into
  /// [netPnl].
  final double commission;

  /// Swap / financing. Signed the same way as [commission].
  final double swap;

  final double? entryPrice;
  final double? exitPrice;
  final double? stopLoss;
  final double? takeProfit;
  final DateTime? openTime;
  final DateTime? closeTime;

  /// Provenance metadata, present only when the export carried it.
  final String? broker;
  final String? accountNumber;
  final String? currency;

  /// What the trader actually earned: gross result plus commission and swap.
  ///
  /// This is the number the journal must show. Importing the gross [profit] alone would
  /// quietly overstate every account that pays swap, which on a prop firm is the difference
  /// between passing and failing an evaluation.
  double get netPnl => profit + commission + swap;

  /// Projects onto the existing domain model the journal and guard already speak.
  ///
  /// [accountId] is supplied by the caller because one file can be imported into any account;
  /// it is never read out of the file itself.
  Trade toTrade({required String accountId}) => Trade(
        id: externalId,
        accountId: accountId,
        symbol: symbol,
        direction: direction,
        lots: volumeLots,
        pnl: netPnl,
        entry: entryPrice,
        exit: exitPrice,
        stop: stopLoss,
        target: takeProfit,
        openTime: openTime,
        closeTime: closeTime,
        setup: null,
        notes: null,
      );

  /// Row shape for the `trades` table. `account_id` / `user_id` are added by the repository,
  /// which is the only layer that knows about RLS and tenant scoping.
  Map<String, dynamic> toPersistenceRow() => <String, dynamic>{
        'external_id': externalId,
        'symbol': symbol,
        'direction': direction == TradeDirection.short ? 'short' : 'long',
        'lots': volumeLots,
        'entry': entryPrice,
        'exit': exitPrice,
        'sl': stopLoss,
        'tp': takeProfit,
        'open_time': openTime?.toUtc().toIso8601String(),
        'close_time': closeTime?.toUtc().toIso8601String(),
        'pnl': netPnl,
        'commission': commission,
        'swap': swap,
      };

  /// Copy used by the `replaceExisting` duplicate strategy — keeps broker-provided costs and
  /// provenance instead of resetting them.
  TradeRecord copyWith({
    double? profit,
    double? commission,
    double? swap,
    double? entryPrice,
    double? exitPrice,
    double? stopLoss,
    double? takeProfit,
    DateTime? openTime,
    DateTime? closeTime,
  }) =>
      TradeRecord(
        externalId: externalId,
        symbol: symbol,
        direction: direction,
        volumeLots: volumeLots,
        profit: profit ?? this.profit,
        commission: commission ?? this.commission,
        swap: swap ?? this.swap,
        entryPrice: entryPrice ?? this.entryPrice,
        exitPrice: exitPrice ?? this.exitPrice,
        stopLoss: stopLoss ?? this.stopLoss,
        takeProfit: takeProfit ?? this.takeProfit,
        openTime: openTime ?? this.openTime,
        closeTime: closeTime ?? this.closeTime,
        broker: broker,
        accountNumber: accountNumber,
        currency: currency,
      );
}