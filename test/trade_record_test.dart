import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/trade.dart';
import 'package:tradeguard/features/import/domain/trade_record.dart';

void main() {
  final TradeRecord r = TradeRecord(
    externalId: '1001',
    symbol: 'XAUUSD',
    direction: TradeDirection.short,
    volumeLots: 0.5,
    entryPrice: 2345.10,
    exitPrice: 2351.40,
    openTime: DateTime.utc(2026, 4, 15, 8, 30),
    profit: 312,
    commission: -3.5,
    swap: -0.7,
    currency: 'USD',
  );

  group('netPnl', () {
    test('adds commission and swap', () {
      expect(r.netPnl, closeTo(307.80, 0.0001));
    });

    test('is the gross profit when there are no costs', () {
      const TradeRecord bare = TradeRecord(
        externalId: '1',
        symbol: 'EURUSD',
        direction: TradeDirection.long,
        volumeLots: 1,
        profit: 50,
      );
      expect(bare.netPnl, 50);
    });
  });

  group('toTrade', () {
    test('projects onto the existing domain model', () {
      final Trade t = r.toTrade(accountId: 'acc_eval_100k');
      expect(t.id, '1001');
      expect(t.accountId, 'acc_eval_100k');
      expect(t.symbol, 'XAUUSD');
      expect(t.direction, TradeDirection.short);
      expect(t.lots, 0.5);
      // The journal must show what was actually earned, not the gross figure.
      expect(t.pnl, closeTo(307.80, 0.0001));
      expect(t.entry, 2345.10);
      expect(t.exit, 2351.40);
      expect(t.openTime, DateTime.utc(2026, 4, 15, 8, 30));
    });

    test('carries the account from the caller, never from the file', () {
      expect(r.toTrade(accountId: 'acc_b').accountId, 'acc_b');
    });
  });

  group('toPersistenceRow', () {
    test('matches the trades table shape', () {
      final Map<String, dynamic> row = r.toPersistenceRow();
      expect(row['external_id'], '1001');
      expect(row['symbol'], 'XAUUSD');
      expect(row['direction'], 'short');
      expect(row['lots'], 0.5);
      expect(row['entry'], 2345.10);
      expect(row['sl'], isNull);
      expect(row['pnl'], closeTo(307.80, 0.0001));
      expect(row['commission'], -3.5);
      expect(row['swap'], -0.7);
      expect(row['open_time'], '2026-04-15T08:30:00.000Z');
    });

    test('writes long as long', () {
      const TradeRecord long = TradeRecord(
        externalId: '1',
        symbol: 'EURUSD',
        direction: TradeDirection.long,
        volumeLots: 1,
        profit: 10,
      );
      expect(long.toPersistenceRow()['direction'], 'long');
    });

    test('omits absent timestamps rather than inventing them', () {
      const TradeRecord bare = TradeRecord(
        externalId: '1',
        symbol: 'EURUSD',
        direction: TradeDirection.long,
        volumeLots: 1,
        profit: 10,
      );
      expect(bare.toPersistenceRow()['open_time'], isNull);
      expect(bare.toPersistenceRow()['close_time'], isNull);
    });
  });

  group('copyWith', () {
    test('keeps provenance and costs when restating a trade', () {
      final TradeRecord updated = r.copyWith(profit: 999);
      expect(updated.profit, 999);
      expect(updated.commission, -3.5);
      expect(updated.currency, 'USD');
      expect(updated.externalId, '1001');
      expect(updated.openTime, r.openTime);
    });
  });
}