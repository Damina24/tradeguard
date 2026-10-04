import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/account.dart';
import 'package:tradeguard/core/services/broker_connect_service.dart';

BrokerConnectionRequest _request({
  String login = '5012345',
  String password = 'sup3rSecret',
  String server = 'FTMO-Demo',
  String platform = 'mt5',
  String nickname = 'FTMO EVAL 100K',
  double initialBalance = 100000,
  double profitTarget = 8000,
  double dailyLossLimit = 5000,
  double maxDrawdown = 10000,
}) =>
    BrokerConnectionRequest(
      login: login,
      password: password,
      server: server,
      platform: platform,
      nickname: nickname,
      phase: AccountPhase.eval,
      currency: 'USD',
      initialBalance: initialBalance,
      profitTarget: profitTarget,
      dailyLossLimit: dailyLossLimit,
      maxDrawdown: maxDrawdown,
      drawdownType: DrawdownType.trailing,
      propFirm: 'FTMO',
    );

void main() {
  group('validateConnection', () {
    test('accepts a well-formed request', () {
      expect(validateConnection(_request()), isEmpty);
    });

    test('rejects an empty or non-numeric account number', () {
      expect(validateConnection(_request(login: '')), contains('login'));
      expect(validateConnection(_request(login: 'ABC123')), contains('login'));
    });

    test('rejects a missing password and server', () {
      final errors = validateConnection(_request(password: '', server: '  '));
      expect(errors, contains('password'));
      expect(errors, contains('server'));
    });

    test('rejects an unsupported platform', () {
      expect(validateConnection(_request(platform: 'mt3')), contains('platform'));
      // Case is normalised upstream by the dropdown, so only exact values are accepted here.
      expect(validateConnection(_request(platform: 'MT5')), contains('platform'));
    });

    test('rejects a blank nickname', () {
      expect(validateConnection(_request(nickname: '   ')), contains('nickname'));
    });

    test('rejects non-positive prop rules', () {
      final errors = validateConnection(
        _request(
          initialBalance: 0,
          profitTarget: -1,
          dailyLossLimit: 0,
          maxDrawdown: 0,
        ),
      );
      expect(
        errors.keys,
        containsAll(<String>[
          'initialBalance',
          'profitTarget',
          'dailyLossLimit',
          'maxDrawdown',
        ]),
      );
    });

    test('reports every bad field at once so the user can fix them in one pass',
        () {
      final errors = validateConnection(
        _request(login: '', nickname: '', maxDrawdown: 0),
      );
      expect(errors.length, greaterThanOrEqualTo(3));
    });
  });

  group('connectedAccount', () {
    test('carries the MetaAPI id and the prop rules', () {
      final account = connectedAccount(
        _request(),
        'meta-123',
        now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      expect(account.id, 'acc_1700000000000');
      expect(account.metaapiAccountId, 'meta-123');
      expect(account.nickname, 'FTMO EVAL 100K');
      expect(account.phase, AccountPhase.eval);
      expect(account.drawdownType, DrawdownType.trailing);
      expect(account.propFirm, 'FTMO');
      expect(account.dailyLossLimit, 5000);
      expect(account.maxDrawdown, 10000);
      expect(account.equityGuardEnabled, isTrue);
    });

    test('starts live numbers at the initial balance rather than inventing P&L', () {
      final account = connectedAccount(_request(), 'meta-123');
      expect(account.equity, account.initialBalance);
      expect(account.balance, account.initialBalance);
      expect(account.peakEquity, account.initialBalance);
      expect(account.dailyPnl, 0);
    });

    test('trims the nickname', () {
      final account = connectedAccount(_request(nickname: '  My EVAL  '), 'meta-1');
      expect(account.nickname, 'My EVAL');
    });
  });

  group('MockBrokerConnectService', () {
    test('is reported as stubbed and returns a deterministic id', () async {
      final service = MockBrokerConnectService(latency: Duration.zero);
      expect(service.isStubbed, isTrue);

      final first = await service.connectBroker(_request());
      final second = await service.connectBroker(_request());
      expect(first, 'mock_meta_5012345');
      expect(second, first);
    });

    test('records the request without ever keeping the password', () async {
      final service = MockBrokerConnectService(latency: Duration.zero);
      await service.connectBroker(_request(password: 'sup3rSecret'));

      expect(service.receivedBodies, hasLength(1));
      expect(service.receivedBodies.single, isNot(contains('password')));
      expect(service.receivedBodies.single['login'], '5012345');
      expect(service.receivedBodies.single['server'], 'FTMO-Demo');
      expect(service.receivedBodies.single['platform'], 'mt5');
    });

    test('throws a user-safe message on an invalid request', () async {
      final service = MockBrokerConnectService(latency: Duration.zero);
      await expectLater(
        service.connectBroker(_request(login: 'nope')),
        throwsA(isA<BrokerConnectException>()),
      );
      expect(service.receivedBodies, isEmpty);
    });
  });

  group('BrokerConnectionRequest.toFunctionBody', () {
    test('sends only the four fields the Edge Function expects', () {
      final body = _request().toFunctionBody();
      expect(
        body.keys.toSet(),
        <String>{'login', 'password', 'server', 'platform'},
      );
      // No equity, guard state or account number beyond the broker login travels with this call.
      expect(body.containsKey('equity'), isFalse);
      expect(body.containsKey('daily_loss_limit'), isFalse);
    });

    test('platforms match the supported list', () {
      expect(BrokerConnectionRequest.platforms, <String>['mt5', 'mt4', 'ctrader']);
    });
  });
}
