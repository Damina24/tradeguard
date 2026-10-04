import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/account.dart';
import 'package:tradeguard/core/services/account_repository.dart';
import 'package:tradeguard/core/services/broker_connect_service.dart';
import 'package:tradeguard/core/services/providers.dart';

BrokerConnectionRequest _request({String login = '5012345'}) =>
    BrokerConnectionRequest(
      login: login,
      password: 'sup3rSecret',
      server: 'FTMO-Demo',
      platform: 'mt5',
      nickname: 'My EVAL',
      phase: AccountPhase.eval,
      currency: 'USD',
      initialBalance: 100000,
      profitTarget: 8000,
      dailyLossLimit: 5000,
      maxDrawdown: 10000,
      drawdownType: DrawdownType.trailing,
    );

/// Always rejects, standing in for a MetaAPI refusal.
class ThrowingConnectService implements BrokerConnectService {
  @override
  bool get isStubbed => false;

  @override
  Future<String> connectBroker(BrokerConnectionRequest request) async {
    throw const BrokerConnectException('The broker rejected those details.');
  }
}

void main() {
  group('ConnectAccountNotifier', () {
    test('connecting persists the account through the repository', () async {
      final repo = MockAccountRepository();
      final notifier = ConnectAccountNotifier(
        MockBrokerConnectService(latency: Duration.zero),
        AccountsNotifier(repo),
      );

      final id = await notifier.connect(_request());

      expect(id, 'mock_meta_5012345');
      expect(notifier.state.status, ConnectStatus.success);

      final accounts = await repo.fetchAccounts();
      expect(accounts.length, 3);
      final TradingAccount added =
          accounts.firstWhere((TradingAccount a) => a.metaapiAccountId != null);
      expect(added.nickname, 'My EVAL');
      expect(added.equityGuardEnabled, isTrue);
      expect(added.equityGuardEnabled, isTrue);
    });

    test('the persisted row carries the account id, never the password', () async {
      final repo = MockAccountRepository();
      final notifier = ConnectAccountNotifier(
        MockBrokerConnectService(latency: Duration.zero),
        AccountsNotifier(repo),
      );

      await notifier.connect(_request());

      final accounts = await repo.fetchAccounts();
      final String serialised = accounts
          .map((TradingAccount a) => a.toJson().toString())
          .join();
      expect(serialised, contains('mock_meta_5012345'));
      expect(serialised, isNot(contains('sup3rSecret')));
    });

    test('an invalid request fails without calling the service', () async {
      final MockBrokerConnectService service =
          MockBrokerConnectService(latency: Duration.zero);
      final notifier = ConnectAccountNotifier(
        service,
        AccountsNotifier(MockAccountRepository()),
      );

      final id = await notifier.connect(_request(login: 'not-a-number'));

      expect(id, isNull);
      expect(notifier.state.status, ConnectStatus.failure);
      expect(notifier.state.message, 'Account number must be digits only.');
      expect(service.receivedBodies, isEmpty);
    });

    test('a broker rejection becomes a failure state, not a crash', () async {
      final notifier = ConnectAccountNotifier(
        ThrowingConnectService(),
        AccountsNotifier(MockAccountRepository()),
      );

      final id = await notifier.connect(_request());

      expect(id, isNull);
      expect(notifier.state.status, ConnectStatus.failure);
      expect(notifier.state.message, 'The broker rejected those details.');
    });

    test('reports the stub flag from the underlying service', () {
      expect(
        ConnectAccountNotifier(
          MockBrokerConnectService(latency: Duration.zero),
          AccountsNotifier(MockAccountRepository()),
        ).isStubbed,
        isTrue,
      );
      expect(
        ConnectAccountNotifier(
          ThrowingConnectService(),
          AccountsNotifier(MockAccountRepository()),
        ).isStubbed,
        isFalse,
      );
    });

    test('reset returns to idle', () async {
      final notifier = ConnectAccountNotifier(
        MockBrokerConnectService(latency: Duration.zero),
        AccountsNotifier(MockAccountRepository()),
      );
      await notifier.connect(_request(login: ''));
      expect(notifier.state.status, ConnectStatus.failure);

      notifier.reset();
      expect(notifier.state.status, ConnectStatus.idle);
      expect(notifier.state.message, isNull);
    });
  });
}
