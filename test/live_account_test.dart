import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/live_account.dart';
import 'package:tradeguard/features/guard/data/live_account_repository.dart';
import 'package:tradeguard/features/guard/data/mock_live_account_repository.dart';

/// The live-account model + the connection-state colour contract.
///
/// The Guard dashboard paints the connection badge GREEN only for
/// [ConnectionState.connected]; red is reserved for `offline`. These tests pin that
/// contract and the JSON mapping so the badge can never regress to "red when
/// healthy" — the exact bug this feature fixes.
void main() {
  group('ConnectionState colour contract', () {
    test('only connected is healthy (the one green state)', () {
      expect(BrokerConnectionState.connected.isHealthy, isTrue);
      expect(BrokerConnectionState.syncing.isHealthy, isFalse);
      expect(BrokerConnectionState.offline.isHealthy, isFalse);
    });

    test('labels are short and factual', () {
      expect(BrokerConnectionState.connected.label, 'LIVE');
      expect(BrokerConnectionState.syncing.label, 'SYNCING');
      expect(BrokerConnectionState.offline.label, 'OFFLINE');
    });
  });

  group('LiveAccountData.fromJson', () {
    test('maps a full payload', () {
      final LiveAccountData d = LiveAccountData.fromJson(<String, dynamic>{
        'account_id': 'acc-1',
        'balance': 103450,
        'equity': 103712.4,
        'connection': 'connected',
        'linked': true,
        'positions': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'p1',
            'symbol': 'XAUUSD',
            'side': 'buy',
            'lots': 0.5,
            'open_price': 2345.1,
            'current_price': 2351.4,
            'pnl': 312,
          },
        ],
        'as_of': '2026-04-20T12:00:00.000Z',
      });

      expect(d.accountId, 'acc-1');
      expect(d.balance, 103450);
      expect(d.equity, 103712.4);
      expect(d.connection, BrokerConnectionState.connected);
      expect(d.linked, isTrue);
      expect(d.positions, hasLength(1));
      expect(d.positions.single.sideLabel, 'BUY');
      expect(d.openPnl, 312);
    });

    test('an unknown connection string falls back to offline', () {
      final LiveAccountData d = LiveAccountData.fromJson(<String, dynamic>{
        'connection': 'something-else',
      });
      expect(d.connection, BrokerConnectionState.offline);
    });

    test('notLinked is offline, unlinked and empty — never red-as-error', () {
      final LiveAccountData d = LiveAccountData.notLinked('acc-2');
      expect(d.linked, isFalse);
      expect(d.connection, BrokerConnectionState.offline);
      expect(d.positions, isEmpty);
      expect(d.openPnl, 0);
    });

    test('openPnl sums every position', () {
      final LiveAccountData d = LiveAccountData.fromJson(<String, dynamic>{
        'positions': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'symbol': 'X', 'side': 'buy', 'lots': 1, 'pnl': 10},
          <String, dynamic>{'id': 'b', 'symbol': 'Y', 'side': 'sell', 'lots': 1, 'pnl': -4},
        ],
      });
      expect(d.openPnl, 6);
    });
  });

  group('MockLiveAccountRepository', () {
    test('answers connected with seeded positions', () async {
      const MockLiveAccountRepository repo = MockLiveAccountRepository();
      final LiveAccountData d = await repo.fetchLive('acc-1');
      expect(d.connection, BrokerConnectionState.connected);
      expect(d.positions, isNotEmpty);
      expect(d.balance, greaterThan(0));
    });
  });

  group('LiveAccountException', () {
    test('carries a trader-safe message', () {
      const LiveAccountException e = LiveAccountException('Could not reach your broker.');
      expect(e.message, 'Could not reach your broker.');
      expect(e.toString(), contains('Could not reach your broker.'));
    });
  });
}
