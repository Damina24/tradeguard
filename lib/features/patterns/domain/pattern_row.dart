/// One row of the Postgres view `v_patterns`, verbatim.
///
/// This class is the whole data contract for pattern analytics. Every number it
/// carries was calculated by SQL in migration 0002:
///
/// ```sql
/// select user_id, symbol, session,
///        extract(dow  from close_time) as dow,
///        extract(hour from close_time) as hour,
///        sum(pnl) as pnl,
///        count(*)  as n,
///        avg(case when pnl > 0 then 1 else 0 end) as win_rate
/// from trades group by 1,2,3,4,5;
/// ```
///
/// So `pnl`, `n` and `win_rate` are *aggregates*, and this layer must never
/// recompute any of them from raw trades — doing so would produce a second,
/// conflicting version of the same statistic. `PatternMetrics` re-groups these
/// rows along a coarser dimension (all symbols together, all hours together) by
/// summing SQL's own sums, which is the only roll-up the client is entitled to.
class PatternRow {
  const PatternRow({
    required this.userId,
    required this.symbol,
    required this.session,
    required this.dayOfWeek,
    required this.hour,
    required this.pnl,
    required this.trades,
    required this.winRate,
  });

  /// `v_patterns.user_id`. Carried so the repository can prove every row it
  /// returns belongs to the signed-in trader; never used to *select* one.
  final String userId;

  /// `v_patterns.symbol` — `trades.symbol` is NOT NULL, so this is only ever
  /// null if the backend sent something the schema forbids.
  final String? symbol;

  /// `v_patterns.session` — nullable on `trades`, so a null group is normal and
  /// must survive the round trip rather than throwing.
  final String? session;

  /// `extract(dow from close_time)`: 0 = Sunday … 6 = Saturday.
  final int? dayOfWeek;

  /// `extract(hour from close_time)`: 0–23.
  final int? hour;

  /// `sum(pnl)` over the group. Note this is the NET persisted `trades.pnl`,
  /// which Tasks 2.1/2.2 write as `profit + commission + swap` — costs are
  /// already inside this number and must not be subtracted again.
  final double pnl;

  /// `count(*)`.
  final int trades;

  /// `avg(case when pnl > 0 then 1 else 0 end)` — a 0…1 fraction, not a percent.
  final double winRate;

  /// Tolerant parse of a `v_patterns` row.
  ///
  /// Postgres returns `numeric` as a JSON number and `extract()` as a double, but
  /// a row that arrives missing a nullable code column is still usable for the
  /// other dimensions — so those become null instead of failing the whole read.
  /// What is NOT tolerated is a row with no count or no money: that is a broken
  /// contract rather than a sparse trade, and a silent zero would fabricate a
  /// pattern out of it.
  factory PatternRow.fromJson(Map<String, dynamic> json) {
    final int? n = _asInt(json['n']);
    final double? pnl = _asDouble(json['pnl']);
    if (n == null || pnl == null) {
      throw const FormatException(
        'Pattern row is missing the n/pnl the view contract guarantees.',
      );
    }
    final double? winRate = _asDouble(json['win_rate']);
    return PatternRow(
      userId: json['user_id'] as String? ?? '',
      symbol: json['symbol'] as String?,
      session: json['session'] as String?,
      dayOfWeek: _asInt(json['dow']),
      hour: _asInt(json['hour']),
      pnl: pnl,
      trades: n,
      // SQL cannot divide by zero, but a 0-trade group would still mean
      // "unmeasured", and inventing 0% or 100% would be a lie either way.
      winRate: (winRate == null || winRate < 0 || winRate > 1) ? 0 : winRate,
    );
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}