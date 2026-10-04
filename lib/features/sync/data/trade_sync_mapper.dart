import '../../../core/models/trade.dart';
import '../../import/data/value_normalizer.dart';
import '../../import/domain/import_issue.dart';
import '../../import/domain/trade_record.dart';

/// Maps a provider's trade record into the canonical [TradeRecord].
///
/// Reuses Task 2.1 wholesale: the same `TradeRecord`, the same [ValueNormalizer] coercions and
/// the same `ImportIssue` vocabulary. There is deliberately NO second normalization model here
/// — a rule change ("a 0-lot trade is invalid") must not be implemented twice and drift.
///
/// What is new is only the *field selection*: a provider names its fields differently from a
/// CSV export, so this class resolves a provider key against several candidate names.
class TradeSyncMapper {
  const TradeSyncMapper();

  /// Provider keys checked for each canonical field, in priority order.
  ///
  /// Kept as data so adding a second provider is a map edit, not a code change.
  static const Map<String, List<String>> fieldKeys = <String, List<String>>{
    'externalId': <String>[
      'id',
      'ticket',
      'dealId',
      'deal_id',
      'positionId',
      'ticketId',
    ],
    'symbol': <String>['symbol', 'instrument', 'pair'],
    'direction': <String>['type', 'direction', 'side'],
    'volume': <String>['volume', 'lots', 'size', 'quantity'],
    'entryPrice': <String>['openPrice', 'open_price', 'entryPrice', 'priceOpen'],
    'exitPrice': <String>['closePrice', 'close_price', 'exitPrice', 'priceClose'],
    'stopLoss': <String>['sl', 'stopLoss', 'slPrice'],
    'takeProfit': <String>['tp', 'takeProfit', 'tpPrice'],
    'profit': <String>['profit', 'pnl', 'pl'],
    'commission': <String>['commission', 'fee'],
    'swap': <String>['swap', 'financing'],
    'openTime': <String>['openTime', 'open_time', 'time', 'entryTime'],
    'closeTime': <String>['closeTime', 'close_time', 'exitTime'],
    'currency': <String>['currency', 'ccy'],
  };

  /// Case-insensitive lookup across a provider record.
  ///
  /// Handles the camelCase and snake_case spellings providers mix freely, so the alias list
  /// above does not need every permutation.
  static dynamic pick(Map<String, dynamic> deal, List<String> keys) {
    final Map<String, dynamic> lower = <String, dynamic>{
      for (final MapEntry<String, dynamic> e in deal.entries)
        e.key.toLowerCase(): e.value,
    };
    for (final String k in keys) {
      final dynamic v = lower[k.toLowerCase()];
      if (v != null) return v;
    }
    return null;
  }

  /// Converts one provider record, or null when it cannot be trusted.
  ///
  /// Returns null and records an [ImportIssue] for a record with no identifier (nothing to
  /// dedupe against, so storing it would be unsafe) or with an unusable symbol, direction or
  /// volume. One bad record must never fail the whole sync.
  TradeRecord? map(
    Map<String, dynamic> deal, {
    required List<ImportIssue> issues,
  }) {
    final String id =
        (pick(deal, fieldKeys['externalId']!)?.toString() ?? '').trim();
    if (id.isEmpty) {
      issues.add(const ImportIssue(
        ImportIssueCode.missingRequiredField,
        field: 'trade ID',
        message: 'A trade from your broker had no trade ID and was skipped.',
      ),);
      return null;
    }
final Coerced<String> symbol = ValueNormalizer.symbol(
      pick(deal, fieldKeys['symbol']!)?.toString() ?? '',
    );
    if (!symbol.isValid) {
      issues.add(const ImportIssue(
        ImportIssueCode.missingRequiredField,
        field: 'symbol',
        message: 'A trade from your broker had no symbol and was skipped.',
      ),);
      return null;
    }

    final TradeDirection? direction =
        directionOf(pick(deal, fieldKeys['direction']!));
    if (direction == null) {
      issues.add(const ImportIssue(
        ImportIssueCode.unsupportedDirection,
        field: 'direction',
        message: 'A trade from your broker had an unreadable direction and was '
            'skipped.',
      ),);
      return null;
    }

    final Coerced<double> volume = ValueNormalizer.volume(
      pick(deal, fieldKeys['volume']!)?.toString() ?? '',
    );
    if (!volume.isValid) {
      issues.add(const ImportIssue(
        ImportIssueCode.invalidVolume,
        field: 'volume',
        message: 'A trade from your broker had an unusable volume and was '
            'skipped.',
      ),);
      return null;
    }

    // Optional fields: a provider omitting them is normal, so a bad value degrades to null
    // rather than dropping an otherwise-valid trade. (Task 2.1 is stricter because a *file*
    // column is declared; here the key may simply be absent.)
    double? optionalNum(String field) {
      final Coerced<double> c =
          ValueNormalizer.number(pick(deal, fieldKeys[field]!)?.toString());
      return c.isValid ? c.value : null;
    }

    DateTime? optionalDate(String field) {
      final Coerced<DateTime> c =
          ValueNormalizer.date(pick(deal, fieldKeys[field]!)?.toString());
      return c.isValid ? c.value : null;
    }

    return TradeRecord(
      externalId: id,
      symbol: symbol.value!,
      direction: direction,
      volumeLots: volume.value!,
      entryPrice: optionalNum('entryPrice'),
      exitPrice: optionalNum('exitPrice'),
      stopLoss: optionalNum('stopLoss'),
      takeProfit: optionalNum('takeProfit'),
      openTime: optionalDate('openTime'),
      closeTime: optionalDate('closeTime'),
      profit: optionalNum('profit') ?? 0,
      commission: optionalNum('commission') ?? 0,
      swap: optionalNum('swap') ?? 0,
      currency: _text(pick(deal, fieldKeys['currency']!)),
    );
  }

  /// Providers encode direction as a word (`buy`) or a signed number (`1` / `-1`).
  ///
  /// Reuses [ValueNormalizer.direction] for the word forms so the accepted vocabulary is
  /// defined in exactly one place.
  static TradeDirection? directionOf(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      if (raw > 0) return TradeDirection.long;
      if (raw < 0) return TradeDirection.short;
      return null;
    }
    return ValueNormalizer.direction(raw.toString()).value;
  }

  static String? _text(dynamic v) {
    final String s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }
}