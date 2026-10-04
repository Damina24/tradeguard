/// Canonical field names. Deliberately neutral — a parser maps a broker's column onto one of
/// these and the rest of the app never learns what the column was called.
enum TradeField {
  externalId,
  symbol,
  direction,
  volume,
  entryPrice,
  exitPrice,
  stopLoss,
  takeProfit,
  profit,
  commission,
  swap,
  openTime,
  closeTime,
  currency,
  broker,
  accountNumber,
}

/// Header aliases, normalized to lowercase-with-no-separators.
///
/// This is the ONLY place broker/export vocabulary lives. Adding a new broker's statement is a
/// matter of appending aliases here (or passing a custom [aliases] table) — no parser, domain
/// or UI change.
///
/// Aliases are matched after stripping spaces, dots, dashes, slashes and colons, so
/// `Open Price`, `open_price` and `OPENPRICE` all hit the same entry.
class FieldAliasTable {
  FieldAliasTable({Map<TradeField, List<String>>? aliases})
      : aliases = _normalize(aliases ?? defaultAliases);

  /// Canonical field -> normalized alias list.
  final Map<TradeField, List<String>> aliases;

  static Map<TradeField, List<String>> _normalize(Map<TradeField, List<String>> src) {
    final Map<TradeField, List<String>> out = <TradeField, List<String>>{};
    src.forEach((TradeField f, List<String> names) {
      out[f] = names.map(key).toList();
    });
    return out;
  }

  static const Map<TradeField, List<String>> defaultAliases =
      <TradeField, List<String>>{
    TradeField.externalId: <String>[
      'id', 'deal', 'dealid', 'ticket', 'ticketid', 'order', 'orderid',
      'orderno', 'positionid', 'position', 'no', 'number', 'ref', 'reference',
      'tradeid', 'dealreference',
    ],
    TradeField.symbol: <String>[
      'symbol', 'instrument', 'pair', 'pairs', 'ticker', 'market', 'contract',
      'sym',
    ],
    TradeField.direction: <String>[
      'direction', 'type', 'side', 'ordertype', 'tradetype', 'operation',
      'dealtype', 'buysell', 'bs', 'action',
    ],
    TradeField.volume: <String>[
      'volume', 'lots', 'size', 'qty', 'quantity', 'amount', 'units', 'hand',
      'hands', 'contracts', 'v',
    ],
    TradeField.entryPrice: <String>[
      'openprice', 'priceopen', 'entryprice', 'priceentry', 'open', 'entry',
      'rateopen', 'avgopenprice', 'openrate', 'avgprice',
    ],
    TradeField.exitPrice: <String>[
      'closeprice', 'priceclose', 'exitprice', 'priceexit', 'close', 'exit',
      'rateclose', 'avgcloseprice', 'exitrate',
    ],
    TradeField.stopLoss: <String>[
      'sl', 'stoploss', 'stop', 'slprice', 'stoplossprice',
    ],
    TradeField.takeProfit: <String>[
      'tp', 'takeprofit', 'target', 'targetprice', 'tpprice', 'takeprofitprice',
    ],
    TradeField.profit: <String>[
      'profit', 'pnl', 'pl', 'profitloss', 'realizedpnl', 'realisedpnl',
      'result', 'netprofit', 'grossprofit', 'p&l', 'profitlossusd',
    ],
    TradeField.commission: <String>[
      'commission', 'comm', 'commissionusd', 'fee', 'fees', 'brokerage',
    ],
    TradeField.swap: <String>[
      'swap', 'swaps', 'financing', 'financingfee', 'interest', 'carry',
      'rollover',
    ],
    TradeField.openTime: <String>[
      'opentime', 'timeopen', 'opened', 'opendate', 'dateopen', 'entrytime',
      'entrydate', 'entrydateandtime', 'time', 'date', 'datetime',
      'datetimeopen', 'openedat',
    ],
    TradeField.closeTime: <String>[
      'closetime', 'timeclose', 'closed', 'closedate', 'dateclose', 'exittime',
'exitdate', 'exitdatetime', 'closedat',
    ],
    TradeField.currency: <String>[
      'currency', 'ccy', 'depositcurrency', 'accountcurrency',
    ],
    TradeField.broker: <String>[
      'broker', 'brokername', 'provider', 'server', 'servers',
    ],
    TradeField.accountNumber: <String>[
      'account', 'accountno', 'accountnumber', 'login', 'accountid',
      'accountlogin', 'investorid',
    ],
  };

  /// Fields a statement must provide for a row to be importable.
  ///
  /// Deliberately minimal: symbol, direction, size and an identifier are the irreducible
  /// minimum for a journal entry. Everything else degrades to null rather than failing the
  /// row, so a summary statement still imports.
  static const Set<TradeField> required = <TradeField>{
    TradeField.externalId,
    TradeField.symbol,
    TradeField.direction,
    TradeField.volume,
  };

  /// The fields a report normally has but may legitimately omit.
  static const Set<TradeField> optional = <TradeField>{
    TradeField.entryPrice,
    TradeField.exitPrice,
    TradeField.stopLoss,
    TradeField.takeProfit,
    TradeField.profit,
    TradeField.commission,
    TradeField.swap,
    TradeField.openTime,
    TradeField.closeTime,
    TradeField.currency,
    TradeField.broker,
    TradeField.accountNumber,
  };
/// Collapses a raw header to its comparison key: lowercase, alphanumerics only.
  static String key(String raw) =>
      raw.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  /// Resolves one header cell, or null when it is not a field we know.
  TradeField? resolve(String rawHeader) {
    final String k = key(rawHeader);
    if (k.isEmpty) return null;
    for (final MapEntry<TradeField, List<String>> e in aliases.entries) {
      if (e.value.contains(k)) return e.key;
    }
    // Fall back to a suffix match so `Order Ticket` still resolves, but exact matches above
    // always win, so `Close Time` never beats a plain `Time`.
    for (final MapEntry<TradeField, List<String>> e in aliases.entries) {
      for (final String alias in e.value) {
        if (k.length > alias.length && k.endsWith(alias)) return e.key;
      }
    }
    return null;
  }

  /// Column index -> field, for one header row.
  Map<int, TradeField> mapHeader(List<String> header) {
    final Map<int, TradeField> out = <int, TradeField>{};
    for (int i = 0; i < header.length; i++) {
      final TradeField? f = resolve(header[i]);
      // First column wins a contested alias: a report repeating a field later is ignored
      // rather than overwriting the primary column.
      if (f != null && !out.containsValue(f)) out[i] = f;
    }
    return out;
  }

  /// Required fields absent from [columns].
  List<TradeField> missingRequired(Map<int, TradeField> columns) {
    final Set<TradeField> present = columns.values.toSet();
    return required.where((TradeField f) => !present.contains(f)).toList();
  }

  /// Canonical, trader-facing name for a field. Used in error copy so a broker column name
  /// never reaches the UI.
  static String label(TradeField field) {
    switch (field) {
      case TradeField.externalId:
        return 'trade ID';
      case TradeField.symbol:
        return 'symbol';
      case TradeField.direction:
        return 'direction';
      case TradeField.volume:
        return 'volume';
      case TradeField.entryPrice:
        return 'entry price';
      case TradeField.exitPrice:
        return 'exit price';
      case TradeField.stopLoss:
        return 'stop loss';
      case TradeField.takeProfit:
        return 'take profit';
      case TradeField.profit:
        return 'profit';
      case TradeField.commission:
        return 'commission';
      case TradeField.swap:
        return 'swap';
      case TradeField.openTime:
        return 'open time';
      case TradeField.closeTime:
        return 'close time';
      case TradeField.currency:
        return 'currency';
      case TradeField.broker:
        return 'broker';
      case TradeField.accountNumber:
        return 'account number';
    }
  }
}
