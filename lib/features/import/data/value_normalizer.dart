import '../../../../core/models/trade.dart';

/// Outcome of trying to read one cell as one field.
///
/// Three outcomes, not two, because a blank cell is NOT an error: an export that simply has
/// no commission column must still import. [blank] distinguishes "absent" from "unusable".
class Coerced<T> {
  const Coerced.value(this.value)
      : blank = false,
        reason = null;

  const Coerced.blank()
      : value = null,
        blank = true,
        reason = null;

  const Coerced.invalid(this.reason)
      : value = null,
        blank = false;

  final T? value;

  /// True when the source cell was empty or only whitespace.
  final bool blank;

  /// Why the cell could not be read. Trader-safe wording, safe to show.
  final String? reason;

  bool get isValid => value != null;
}

/// Converts raw statement cells into canonical domain values.
///
/// Every conversion in the importer goes through here, which keeps the parsers thin and makes
/// the messy cases (European decimals, `1.234,56`, `1,234.56`, parenthesised negatives,
/// `USD 1 234.56`, `SELL`, `-1`) testable without a parser involved.
class ValueNormalizer {
  ValueNormalizer._();

  /// Above this a "volume" is a data-entry accident rather than a trade.
  static const double maxPlausibleLots = 10000.0;

  /// Windows epoch, used by exports that quote dates as Excel serials.
  static final DateTime excelEpoch = DateTime.utc(1899, 12, 30);

  // ---- numbers ----

  /// Parses a money/quantity cell.
  ///
  /// Tolerates currency symbols and codes, thousands separators, both decimal conventions and
  /// accounting-style negatives `(12.50)`. The separator appearing LAST is the decimal point,
  /// so a European `1.234,56` and a US `1,234.56` both read as 1234.56.
  static Coerced<double> number(String? raw) {
    // "Blank" means the cell was empty. Text that reduces to nothing once the currency and
    // separators are stripped ("abc") is invalid, not blank — the difference decides whether
    // a row is skipped or the column is simply treated as absent.
    if ((raw ?? '').trim().isEmpty) return const Coerced<double>.blank();
    final String s = tidy(raw);
    if (s.isEmpty) return const Coerced<double>.invalid('not a number');

    bool negative = false;
    String body = s;
    if (body.startsWith('(') && body.endsWith(')')) {
      negative = true;
      body = body.substring(1, body.length - 1).trim();
    }
    if (body.startsWith('-')) {
      negative = true;
      body = body.substring(1).trim();
    } else if (body.startsWith('+')) {
      body = body.substring(1).trim();
    }

    final int lastComma = body.lastIndexOf(',');
    final int lastDot = body.lastIndexOf('.');
    int decimalAt = -1;
    if (lastComma >= 0 && lastDot >= 0) {
      decimalAt = lastComma > lastDot ? lastComma : lastDot;
    } else if (lastComma >= 0) {
      // A lone comma is decimal only when it splits off 1-2 trailing digits ("0,50").
      final int tail = body.length - lastComma - 1;
      decimalAt = (tail > 0 && tail <= 2) ? lastComma : -1;
    } else if (lastDot >= 0) {
      // Same rule for a lone dot ("1.500" is 1500, "1.50" is 1.5).
      final int tail = body.length - lastDot - 1;
      decimalAt = (tail > 0 && tail <= 2) ? lastDot : -1;
    }

    final StringBuffer digits = StringBuffer();
    for (int i = 0; i < body.length; i++) {
      final String c = body[i];
      if (isDigit(c)) {
        digits.write(c);
      } else if (i == decimalAt) {
        digits.write('.');
      } else if (c != ',' && c != '.' && c != ' ') {
        return const Coerced<double>.invalid('not a number');
      }
    }

    final String normalized = digits.toString();
    if (normalized.isEmpty || normalized == '.') {
      return const Coerced<double>.invalid('not a number');
    }
    final double? parsed = double.tryParse(normalized);
    if (parsed == null || !parsed.isFinite) {
      return const Coerced<double>.invalid('not a number');
    }
    return Coerced<double>.value(negative ? -parsed : parsed);
  }

  /// Parses a size/volume cell and enforces plausibility.
  ///
  /// Zero, negative and absurd sizes are rejected here rather than silently clamped: a 0-lot
  /// trade cannot exist and a 99999-lot one is almost always a shifted decimal.
  static Coerced<double> volume(String? raw) {
    final Coerced<double> n = number(raw);
    if (!n.isValid) return n;
    final double v = n.value!;
    if (v <= 0) {
      return const Coerced<double>.invalid('volume must be greater than zero');
    }
    if (v > maxPlausibleLots) {
      return const Coerced<double>.invalid('volume is too large to be a real trade');
    }
    return Coerced<double>.value(v);
  }

  // ---- text ----

  /// Canonical instrument code: upper-cased with broker decorations removed.
  ///
  /// `XAUUSD.m`, `XAUUSD.pro`, `#XAUUSD` and `XAUUSD_ecn` all become `XAUUSD`.
  static Coerced<String> symbol(String? raw) {
    final String s = (raw ?? '').trim();
    if (s.isEmpty) return const Coerced<String>.blank();
    String out = s.toUpperCase().replaceAll(' ', '');
    if (out.startsWith('#')) out = out.substring(1);
    final int cut = out.indexOf(RegExp(r'[._\-]'));
    if (cut > 0) out = out.substring(0, cut);
    if (out.isEmpty) return const Coerced<String>.invalid('symbol is not readable');
    return Coerced<String>.value(out);
  }

  /// Maps a broker direction onto [TradeDirection].
  ///
  /// Accepts long/short, buy/sell, B/S, +1/-1 and the limit/stop variants. Anything else is
  /// rejected rather than guessed — defaulting an unknown direction to "long" would silently
  /// invert half a trader's P&L.
  static Coerced<TradeDirection> direction(String? raw) {
    final String s = (raw ?? '').trim().toUpperCase();
    if (s.isEmpty) return const Coerced<TradeDirection>.blank();
    switch (s) {
      case 'BUY':
      case 'BUY LIMIT':
      case 'BUY STOP':
      case 'BUYLIMIT':
      case 'BUYSTOP':
      case 'BUY_STOP':
      case 'LONG':
      case 'B':
      case 'L':
      case '1':
      case '+1':
      case 'IN':
      case 'OPEN':
        return const Coerced<TradeDirection>.value(TradeDirection.long);
      case 'SELL':
      case 'SELL LIMIT':
      case 'SELL STOP':
      case 'SELLLIMIT':
      case 'SELLSTOP':
      case 'SELL_STOP':
      case 'SHORT':
      case 'S':
      case '-1':
      case 'OUT':
      case 'CLOSE':
        return const Coerced<TradeDirection>.value(TradeDirection.short);
    }
    return const Coerced<TradeDirection>.invalid('direction is not buy or sell');
  }

  // ---- dates ----

  /// Formats tried in order. Year-first is unambiguous and wins; the day/month orders are
  /// resolved by taking the first reading that yields a real calendar date.
  static const List<String> timestampFormats = <String>[
    'yyyy-MM-dd HH:mm:ss',
    'yyyy-MM-dd HH:mm',
    'yyyy-MM-ddTHH:mm:ss',
    'yyyy-MM-ddTHH:mm',
    'yyyy/MM/dd HH:mm:ss',
    'yyyy/MM/dd HH:mm',
    'dd/MM/yyyy HH:mm:ss',
    'dd/MM/yyyy HH:mm',
    'dd.MM.yyyy HH:mm:ss',
    'dd.MM.yyyy HH:mm',
    'dd-MM-yyyy HH:mm:ss',
    'dd-MM-yyyy HH:mm',
    'MM/dd/yyyy HH:mm:ss',
    'MM/dd/yyyy HH:mm',
    'yyyy-MM-dd',
    'yyyy/MM/dd',
    'dd/MM/yyyy',
    'dd.MM.yyyy',
    'dd-MM-yyyy',
    'MM/dd/yyyy',
    'dd MMM yyyy HH:mm',
    'dd MMM yyyy',
  ];

  /// Parses a date/timestamp cell into UTC.
  ///
  /// Handles ISO-8601 (with or without a zone), the broker layouts above, month names and
  /// Excel serial numbers. Unparseable input is an error, never a silent epoch.
  static Coerced<DateTime> date(String? raw) {
    final String s = (raw ?? '').trim();
    if (s.isEmpty) return const Coerced<DateTime>.blank();

    final DateTime? iso = _tryIso(s);
    if (iso != null) return Coerced<DateTime>.value(iso);

    final DateTime? serial = _tryExcelSerial(s);
    if (serial != null) return Coerced<DateTime>.value(serial);

    for (int i = 0; i < timestampFormats.length; i++) {
      final DateTime? d = _tryFormat(s, timestampFormats[i]);
      if (d != null) return Coerced<DateTime>.value(d);
    }
    return const Coerced<DateTime>.invalid('date is not a recognised format');
  }

  static DateTime? _tryIso(String s) {
    // Bare `yyyy-MM-dd HH:mm:ss` is not ISO to DateTime.parse; normalise the separator.
    final String candidate =
        s.contains(' ') && !s.contains('T') ? s.replaceFirst(' ', 'T') : s;
    final DateTime? d = DateTime.tryParse(candidate);
    if (d == null) return null;

    // DateTime.parse ROLLS OVER impossible dates rather than rejecting them: 2026-02-31
    // becomes 2026-03-03. Comparing against the literal y-m-d in the text is what lets the
    // importer promise that a bad date is reported instead of quietly importing a wrong day.
    final RegExpMatch? ymd =
        RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(candidate);
    if (ymd != null) {
      final int y = int.parse(ymd.group(1)!);
      final int m = int.parse(ymd.group(2)!);
      final int day = int.parse(ymd.group(3)!);
      if (d.year != y || d.month != m || d.day != day) return null;
    }

    return d.isUtc
        ? d
        : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);
  }

  /// An all-digit value in a plausible Excel range is a serial, not a year.
  static DateTime? _tryExcelSerial(String s) {
    if (!RegExp(r'^\d{5}(\.\d+)?$').hasMatch(s)) return null;
    final double? serial = double.tryParse(s);
    if (serial == null || serial < 1) return null;
    final DateTime d = excelEpoch.add(Duration(days: serial.round()));
    if (d.year < 1990 || d.year > 2100) return null;
    return d;
  }

  /// Builds a UTC date, rejecting values the calendar would roll over (31/02, hour 25).
  static DateTime? build(int y, int mo, int d, int h, int mi, int s) {
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    if (h > 23 || mi > 59 || s > 59) return null;
    if (y < 1970 || y > 2100) return null;
    final DateTime dt = DateTime.utc(y, mo, d, h, mi, s);
    // DateTime rolls impossible days forward (Feb 31 -> Mar 3); reject rather than accept.
    if (dt.month != mo || dt.day != d) return null;
    return dt;
  }

  /// Tries one layout. Compile-on-demand keeps the class simple; the format list is short and
  /// an import parses a file once.
  static DateTime? _tryFormat(String s, String format) {
    final _DatePattern? p = _patternCache[format];
    if (p == null) return null;
    final RegExpMatch? m = p.regex.firstMatch(s);
    return m == null ? null : p.parse(m);
  }

  /// Strips a currency code/symbol and collapses separators, keeping digits and sign.
  static String tidy(String? raw) {
    final String s = (raw ?? '').trim();
    if (s.isEmpty) return '';
    final String stripped = s.replaceAll(
      RegExp(r'^(USD|EUR|GBP|JPY|AUD|CAD|CHF|ZAR|USDT)\s+', caseSensitive: false),
      '',
    );
    return stripped
        .replaceAll(RegExp(r'[^0-9,.\-+() ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool isDigit(String c) =>
      c.length == 1 && c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  /// Compiled layouts, built once.
  static final Map<String, _DatePattern> _patternCache = <String, _DatePattern>{
    for (final String f in timestampFormats) f: _DatePattern(f),
  };
}

/// Compiled matcher for one entry in [ValueNormalizer.timestampFormats].
///
/// `DateFormat` is deliberately not used: it silently accepts impossible dates such as
/// 31/02, which would defeat the invalid-date validation this importer promises.
class _DatePattern {
  _DatePattern(String format) {
    // `dd MMM yyyy HH:mm` splits into four tokens, so the date portion is everything before
    // the time tokens — not just parts[0], which for a month-name layout would be `dd` and
    // would hide the `MMM`.
    final List<String> parts = format.split(' ');
    final int dateTokens = parts.indexWhere((String p) => p.contains('H'));
    final List<String> dateParts =
        dateTokens < 0 ? parts : parts.sublist(0, dateTokens);
    hasTime = dateTokens >= 0;
    final String datePart = dateParts.join(' ');
    yearFirst = datePart.startsWith('yyyy');
    dayFirst = datePart.startsWith('dd');
    monthIsName = datePart.contains('MMM');

    // Interpolated into a NON-raw string below: raw strings (r'...') do not interpolate, so
    // writing r'(\d{4})$sep...' would leave a literal "$sep" in the pattern.
    final String sep = datePart.contains('-')
        ? r'\-'
        : datePart.contains('/')
            ? '/'
            : datePart.contains('.')
                ? r'\.'
                : r'\s';

    final String time =
        hasTime ? r'[\sT]+(\d{1,2}):(\d{2})(?::(\d{2}))?' : '';
    final String dateRx;
    if (monthIsName) {
      dateRx = r'(\d{1,2})[\s]+([A-Za-z]{3,9})[\s]+(\d{4})';
    } else if (yearFirst) {
      dateRx = '(\\d{4})$sep(\\d{1,2})$sep(\\d{1,2})';
    } else if (dayFirst) {
      dateRx = '(\\d{1,2})$sep(\\d{1,2})$sep(\\d{4})';
    } else {
      dateRx = '(\\d{1,2})$sep(\\d{1,2})$sep(\\d{4})';
    }
    // Anchored at both ends: without this, "2026-04-15 25:00" would satisfy `yyyy-MM-dd` by
    // matching only the date part, and an impossible hour would slip through as valid.
    regex = RegExp('^$dateRx$time\$');
  }

  late final bool hasTime;
  late final bool yearFirst;
  late final bool dayFirst;
  late final bool monthIsName;
  late final RegExp regex;

  /// Reads the matched groups into a UTC [DateTime], or null when the text does not describe
  /// a real date.
  DateTime? parse(RegExpMatch m) {
    int group(int i) => int.parse(m.group(i)!);

    if (monthIsName) {
      final int month = _monthFromName(m.group(2)!);
      if (month == 0) return null;
      if (!hasTime) return ValueNormalizer.build(group(3), month, group(1), 0, 0, 0);
      return ValueNormalizer.build(
        group(3),
        month,
        group(1),
        group(4),
        group(5),
        m.group(6) == null ? 0 : group(6),
      );
    }

    final int y;
    final int mo;
    final int d;
    if (yearFirst) {
      y = group(1);
      mo = group(2);
      d = group(3);
    } else if (dayFirst) {
      d = group(1);
      mo = group(2);
      y = group(3);
    } else {
      mo = group(1);
      d = group(2);
      y = group(3);
    }
    if (!hasTime) return ValueNormalizer.build(y, mo, d, 0, 0, 0);
    return ValueNormalizer.build(
      y,
      mo,
      d,
      group(4),
      group(5),
      m.group(6) == null ? 0 : group(6),
    );
  }

  static int _monthFromName(String name) {
    const Map<String, int> months = <String, int>{
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };
    return months[name.toLowerCase()] ?? 0;
  }
}