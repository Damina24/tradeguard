import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/account.dart';
import 'package:tradeguard/core/services/account_repository.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/features/guard/presentation/guard_screen.dart';

/// The Guard screen (the app's home tab) must never hang on a spinner.
///
/// The reported bug: the home page spun a loading indicator for 10+ minutes.
/// The cause was that a null `guardStatusProvider` was rendered as one spinner
/// regardless of WHY it was null — the accounts query still loading, the query
/// having failed, or the trader genuinely having no accounts. When the accounts
/// read never resolved (a stalled network call with no timeout), the spinner had
/// no way out. These tests drive each state and assert the screen resolves to a
/// real loading / empty / error surface instead.
void main() {
  testWidgets('a resolved empty account list shows the empty state, not a '
      'spinner', (WidgetTester tester) async {
    final AccountsNotifier notifier = AccountsNotifier(_EmptyAccounts());
    await notifier.refresh();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          accountsProvider.overrideWith((_) => notifier),
        ],
        child: const MaterialApp(home: GuardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // No infinite spinner: the empty state is a real message with guidance.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No accounts yet'), findsOneWidget);
    expect(find.textContaining('Connect a broker account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed accounts read shows an error state with a retry, not a '
      'spinner', (WidgetTester tester) async {
    final AccountsNotifier notifier = AccountsNotifier(_FailingAccounts());
    await notifier.refresh();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          accountsProvider.overrideWith((_) => notifier),
        ],
        child: const MaterialApp(home: GuardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // The failure is surfaced, never as an empty desk and never as a spinner.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Could not load your accounts'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pending first load shows a spinner that resolves once data '
      'arrives', (WidgetTester tester) async {
    // A repository that answers after a short delay models a real (slow) read.
    final AccountsNotifier notifier =
        AccountsNotifier(_SlowAccounts(const Duration(milliseconds: 50)));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          accountsProvider.overrideWith((_) => notifier),
        ],
        child: const MaterialApp(home: GuardScreen()),
      ),
    );

    // Immediately: still loading, so a spinner is correct and expected.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Once the repository answers, the spinner is replaced by the guard body.
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('DAILY LOSS USED'), findsOneWidget);
  });

  testWidgets('with accounts present the guard renders its metrics', (
    WidgetTester tester,
  ) async {
    final AccountsNotifier notifier = AccountsNotifier(MockAccountRepository());
    await notifier.refresh();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          accountsProvider.overrideWith((_) => notifier),
        ],
        child: const MaterialApp(home: GuardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DRAWDOWN DISTANCE'), findsOneWidget);
    expect(find.text('TO TARGET'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// An account repository that resolves to an empty list — a trader who has
/// connected nothing yet.
class _EmptyAccounts implements AccountRepository {
  @override
  Future<List<TradingAccount>> fetchAccounts() async =>
      const <TradingAccount>[];

  @override
  Future<AccountSnapshot> fetchSnapshot(String accountId) async =>
      throw StateError('no account');

  @override
  Future<TradingAccount> createAccount(TradingAccount account) async =>
      account;

  @override
  Future<void> deleteAccount(String accountId) async {}

  @override
  Future<void> setEquityGuardEnabled(String accountId, bool enabled) async {}

  @override
  Future<void> setCopyEnabled(String accountId, bool enabled) async {}
}

/// An account repository whose read always fails — a stalled or errored
/// backend, which is what used to hang the spinner forever.
class _FailingAccounts implements AccountRepository {
  @override
  Future<List<TradingAccount>> fetchAccounts() async =>
      throw StateError('network down');

  @override
  Future<AccountSnapshot> fetchSnapshot(String accountId) async =>
      throw StateError('no account');

  @override
  Future<TradingAccount> createAccount(TradingAccount account) async =>
      account;

  @override
  Future<void> deleteAccount(String accountId) async {}

  @override
  Future<void> setEquityGuardEnabled(String accountId, bool enabled) async {}

  @override
  Future<void> setCopyEnabled(String accountId, bool enabled) async {}
}

/// An account repository that answers the demo seed after [delay] — models a
/// real read that is merely slow.
class _SlowAccounts implements AccountRepository {
  _SlowAccounts(this.delay);

  final Duration delay;

  @override
  Future<List<TradingAccount>> fetchAccounts() async {
    await Future<void>.delayed(delay);
    return MockAccountRepository().fetchAccounts();
  }

  @override
  Future<AccountSnapshot> fetchSnapshot(String accountId) async =>
      throw StateError('no account');

  @override
  Future<TradingAccount> createAccount(TradingAccount account) async =>
      account;

  @override
  Future<void> deleteAccount(String accountId) async {}

  @override
  Future<void> setEquityGuardEnabled(String accountId, bool enabled) async {}

  @override
  Future<void> setCopyEnabled(String accountId, bool enabled) async {}
}

