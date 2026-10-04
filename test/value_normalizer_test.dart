import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/trade.dart';
import 'package:tradeguard/features/import/data/value_normalizer.dart';

void main() {
  group('number', () {
    test('reads a plain decimal', () {
      expect(ValueNormalizer.number('2345.5').value, 2345.5);
    });

    test('strips a thousands separator', () {
      expect(ValueNormalizer.number('1,234.56').value, 1234.56);
    });

    test('reads the European convention as the same number', () {
      expect(ValueNormalizer.number('1.234,56').value, 1234.56);
    });

    test('treats a lone comma with two trailing digits as decimal', () {
      expect(ValueNormalizer.number('0,50').value, 0.5);
    });

    test('treats a lone comma with three trailing digits as thousands', () {
      expect(ValueNormalizer.number('1,500').value, 1500);
    });

    test('reads an accounting-style negative', () {
      expect(ValueNormalizer.number('(12.50)').value, -12.50);
    });

    test('reads a leading minus', () {
      expect(ValueNormalizer.number('-320.75').value, -320.75);
    });

    test('drops a currency symbol and code', () {
      expect(ValueNormalizer.number(r'$1,234.56').value, 1234.56);
      expect(ValueNormalizer.number('USD 1 234.56').value, 1234.56);
    });

    test('treats blank as blank, not invalid', () {
      final Coerced<double> r = ValueNormalizer.number('   ');
      expect(r.blank, isTrue);
      expect(r.isValid, isFalse);
    });

    test('rejects text', () {
      final Coerced<double> r = ValueNormalizer.number('abc');
      expect(r.isValid, isFalse);
      expect(r.blank, isFalse);
      expect(r.reason, 'not a number');
    });

    test('rejects a value that is not finite', () {
      expect(ValueNormalizer.number('NaN').isValid, isFalse);
      expect(ValueNormalizer.number('Infinity').isValid, isFalse);
    });
  });

  group('volume', () {
    test('accepts a normal size', () {
      expect(ValueNormalizer.volume('0.50').value, 0.5);
    });

    test('rejects zero', () {
      expect(ValueNormalizer.volume('0').isValid, isFalse);
    });

    test('rejects a negative size', () {
      final Coerced<double> r = ValueNormalizer.volume('-1');
      expect(r.isValid, isFalse);
      expect(r.reason, 'volume must be greater than zero');
    });

    test('rejects an implausible size', () {
      final Coerced<double> r = ValueNormalizer.volume('999999');
      expect(r.isValid, isFalse);
      expect(r.reason, contains('too large'));
    });

    test('rejects a non-numeric size', () {
      expect(ValueNormalizer.volume('lots').isValid, isFalse);
    });
  });

  group('symbol', () {
    test('upper-cases', () {
      expect(ValueNormalizer.symbol('eurusd').value, 'EURUSD');
    });

    test('drops a broker suffix', () {
      expect(ValueNormalizer.symbol('XAUUSD.m').value, 'XAUUSD');
      expect(ValueNormalizer.symbol('XAUUSD.pro').value, 'XAUUSD');
      expect(ValueNormalizer.symbol('XAUUSD_ecn').value, 'XAUUSD');
    });

    test('drops a leading hash marker', () {
      expect(ValueNormalizer.symbol('#XAUUSD').value, 'XAUUSD');
    });

    test('keeps digits used by index symbols', () {
      expect(ValueNormalizer.symbol('US30').value, 'US30');
    });

    test('reports blank for an empty cell', () {
      expect(ValueNormalizer.symbol('').blank, isTrue);
    });
  });
group('direction', () {
    test('maps buy variants to long', () {
      for (final String v in <String>[
        'buy',
        'BUY',
        'Long',
        'B',
        '1',
        '+1',
        'BUY LIMIT',
        'buy_stop',
      ]) {
        expect(
          ValueNormalizer.direction(v).value,
          TradeDirection.long,
          reason: v,
        );
      }
    });

    test('maps sell variants to short', () {
      for (final String v in <String>[
        'sell',
        'SELL',
        'Short',
        'S',
        '-1',
        'SELL LIMIT',
        'sell_stop',
      ]) {
        expect(
          ValueNormalizer.direction(v).value,
          TradeDirection.short,
          reason: v,
        );
      }
    });

    test('rejects an unknown direction rather than guessing', () {
      final Coerced<TradeDirection> r = ValueNormalizer.direction('sideways');
      expect(r.isValid, isFalse);
      expect(r.blank, isFalse);
      // The message must not echo the broker's raw value back to the UI.
      expect(r.reason, 'direction is not buy or sell');
    });
  });

  group('date', () {
    test('parses ISO-8601', () {
      expect(
        ValueNormalizer.date('2026-04-15T08:30:00Z').value,
        DateTime.utc(2026, 4, 15, 8, 30),
      );
    });

    test('parses a space-separated ISO-like stamp', () {
      expect(
        ValueNormalizer.date('2026-04-15 08:30:00').value,
        DateTime.utc(2026, 4, 15, 8, 30),
      );
    });

    test('parses a date with no time', () {
      expect(
        ValueNormalizer.date('2026-04-15').value,
        DateTime.utc(2026, 4, 15),
      );
    });

    test('parses day-first with a dot separator', () {
      expect(
        ValueNormalizer.date('15.04.2026 08:30').value,
        DateTime.utc(2026, 4, 15, 8, 30),
      );
    });

    test('parses day-first with a slash', () {
      expect(
        ValueNormalizer.date('15/04/2026 08:30').value,
        DateTime.utc(2026, 4, 15, 8, 30),
      );
    });

    test('resolves an ambiguous slash date by taking the real one', () {
      // 13 cannot be a month, so this must be 13 April.
      expect(
        ValueNormalizer.date('13/04/2026').value,
        DateTime.utc(2026, 4, 13),
      );
    });

    test('parses a month name', () {
      expect(
        ValueNormalizer.date('15 Apr 2026 08:30').value,
        DateTime.utc(2026, 4, 15, 8, 30),
      );
    });

    test('rejects an impossible calendar date', () {
      expect(ValueNormalizer.date('2026-02-31').isValid, isFalse);
      expect(ValueNormalizer.date('31/02/2026').isValid, isFalse);
    });

    test('rejects an impossible hour', () {
      expect(ValueNormalizer.date('2026-04-15 25:00').isValid, isFalse);
    });

    test('rejects free text', () {
      final Coerced<DateTime> r = ValueNormalizer.date('not a date');
      expect(r.isValid, isFalse);
      expect(r.reason, 'date is not a recognised format');
    });

    test('rejects a bare year', () {
      expect(ValueNormalizer.date('2026').isValid, isFalse);
    });

    test('reports blank for an empty cell', () {
      expect(ValueNormalizer.date('').blank, isTrue);
    });
  });
}