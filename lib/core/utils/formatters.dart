import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static final NumberFormat _money = NumberFormat.currency(
    symbol: r'$',
    decimalDigits: 2,
  );
  static final NumberFormat _money0 = NumberFormat.currency(
    symbol: r'$',
    decimalDigits: 0,
  );
  static final NumberFormat _pct = NumberFormat('#,##0.0');

  static String money(double v) => _money.format(v);

  static String moneyShort(double v) {
    final double abs = v.abs();
    if (abs >= 1000) {
      final String suffix = abs >= 1000000 ? 'M' : 'K';
      final double scaled = abs >= 1000000 ? v / 1000000 : v / 1000;
      return '${scaled.toStringAsFixed(1)}$suffix';
    }
    return _money0.format(v);
  }

  static String pct(double v) => '${_pct.format(v)}%';

  static String signed(double v) => '${v >= 0 ? '+' : '-'}${_money0.format(v.abs())}';

  static String date(DateTime d) => DateFormat.yMMMd().format(d);

  static String monthYear(DateTime d) => DateFormat.yMMMM().format(d);

  static String time(DateTime d) => DateFormat.jm().format(d);

  static String timeAgo(DateTime d) {
    final Duration diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
