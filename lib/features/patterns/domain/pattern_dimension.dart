/// The dimensions `v_patterns` is grouped by.
///
/// Sourced from the view, not from imagination: migration 0002 groups
/// `trades` by `user_id, symbol, session, dow, hour`, so those four columns —
/// and only those four — are what the pattern layer can legitimately slice on.
/// `setup` appears in the roadmap's prose and on `trades.setup`, but the view
/// does not project it, so it is deliberately NOT a dimension here until the
/// view is revised. Inventing a client-side roll-up for it would be a second,
/// conflicting source of truth for the same statistic.
enum PatternDimension {
  symbol('symbol'),
  session('session'),
  hour('hour'),
  dayOfWeek('day');

  const PatternDimension(this.label);

  /// Short, trader-readable name for the dimension itself.
  final String label;
}

/// Sort keys offered by the pattern views.
enum PatternSort {
  trades('Trades'),
  netPnl('Net P&L'),
  expectancy('Avg per trade'),
  winRate('Win rate');

  const PatternSort(this.label);

  final String label;
}

enum PatternDirection {
  descending('Highest first'),
  ascending('Lowest first');

  const PatternDirection(this.label);

  final String label;
}

/// Display labels for values that come out of Postgres as raw codes.
class PatternLabels {
  PatternLabels._();

  /// Postgres `extract(dow …)`: 0 = Sunday through 6 = Saturday.
  static const List<String> _days = <String>[
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  static String dayOfWeek(int dow) =>
      (dow >= 0 && dow < _days.length) ? _days[dow] : 'Day $dow';

  /// Hour-of-day as a clock label. A group keyed on an hour the trader did not
  /// trade is never produced by the query, so there is nothing to invent here.
  static String hour(int hour) =>
      '${hour.toString().padLeft(2, '0')}:00';

  /// `trades.session` is nullable, so the view can legitimately return a null
  /// group. It gets a name rather than being dropped, because silently
  /// discarding untagged trades would understate the trader's own sample size.
  static const String untagged = 'Untagged';

  static String session(String? raw) {
    if (raw == null || raw.trim().isEmpty) return untagged;
    final String v = raw.trim();
    return v[0].toUpperCase() + v.substring(1);
  }

  static String symbol(String? raw) =>
      (raw == null || raw.trim().isEmpty) ? untagged : raw.trim();
}