enum TradeDirection { long, short }

class Trade {
  const Trade({
    required this.id,
    required this.accountId,
    required this.symbol,
    required this.direction,
    required this.lots,
    required this.pnl,
    this.entry,
    this.exit,
    this.stop,
    this.target,
    this.openTime,
    this.closeTime,
    this.session,
    this.setup,
    this.grade,
    this.notes,
    this.screenshotUrl,
    this.rMultiple,
    this.commission = 0,
    this.swap = 0,
    this.currency,
  });

  final String id;
  final String accountId;
  final String symbol;
  final TradeDirection direction;
  final double lots;

  /// The persisted NET result (`profit + commission + swap`), written by Task 2.1's importer and
  /// Task 2.2's sync. This is the authoritative number; the UI shows it verbatim.
  final double pnl;

  final double? entry;
  final double? exit;
  final double? stop;
  final double? target;
  final DateTime? openTime;
  final DateTime? closeTime;
  final String? session;
  final String? setup;

  /// Hand-set grade letter. `null` until the trader picks one; it overrides any derived grade.
  final String? grade;

  final String? notes;
  final String? screenshotUrl;
  final double? rMultiple;

  /// Broker costs as stored on the row. Both default to 0, which keeps every pre-2.1 row (and
  /// the mock seed) valid — `pnl` already nets them off.
  final double commission;
  final double swap;

  /// Account currency when the export carried one. Falls back to the account record in the UI.
  final String? currency;

  /// Gross result before costs, recovered from the persisted net plus persisted costs.
  ///
  /// Derived rather than stored because `trades` has no gross column; both inputs are
  /// authoritative persisted values, so this cannot drift from the database.
  double get grossPnl => pnl - commission - swap;

  bool get isWin => pnl > 0;

  /// Immutable update. Only the journal-editable fields are exposed on purpose — money and
  /// execution data always come from the broker, never from user edits.
  Trade copyWith({String? grade, String? notes, String? screenshotUrl}) => Trade(
        id: id,
        accountId: accountId,
        symbol: symbol,
        direction: direction,
        lots: lots,
        pnl: pnl,
        entry: entry,
        exit: exit,
        stop: stop,
        target: target,
        openTime: openTime,
        closeTime: closeTime,
        session: session,
        setup: setup,
        grade: grade ?? this.grade,
        notes: notes ?? this.notes,
        screenshotUrl: screenshotUrl ?? this.screenshotUrl,
        rMultiple: rMultiple,
        commission: commission,
        swap: swap,
        currency: currency,
      );

  factory Trade.fromJson(Map<String, dynamic> json) => Trade(
        id: json['id'] as String,
        accountId: json['account_id'] as String,
        symbol: json['symbol'] as String,
        direction: json['direction'] == 'short'
            ? TradeDirection.short
            : TradeDirection.long,
        lots: (json['lots'] as num).toDouble(),
        pnl: (json['pnl'] as num).toDouble(),
        entry: (json['entry'] as num?)?.toDouble(),
        exit: (json['exit'] as num?)?.toDouble(),
        stop: (json['sl'] as num?)?.toDouble(),
        target: (json['tp'] as num?)?.toDouble(),
        openTime: _dt(json['open_time']),
        closeTime: _dt(json['close_time']),
        session: json['session'] as String?,
        setup: json['setup'] as String?,
        grade: json['grade'] as String?,
        notes: json['notes'] as String?,
        screenshotUrl: json['screenshot_url'] as String?,
        rMultiple: (json['mfe'] as num?)?.toDouble(),
        // Written by the importer and the sync worker since migration 0001; `pnl` is already
        // net of them, so these two columns exist purely to explain that number.
        commission: (json['commission'] as num?)?.toDouble() ?? 0,
        swap: (json['swap'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String?,
      );

  static DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.tryParse(v as String);
}
