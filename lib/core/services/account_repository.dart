import '../models/account.dart';
import 'mock_data.dart';

/// Live numbers for one account at a point in time, as pulled from the broker (via the
/// `equity_snapshots` table written by the `guard-check` Edge Function).
class AccountSnapshot {
  const AccountSnapshot({
    required this.equity,
    required this.balance,
    required this.dailyPnl,
    required this.peakEquity,
    required this.asOf,
  });

  /// Derives a snapshot from the values already carried on [account].
  factory AccountSnapshot.fromAccount(TradingAccount account, {DateTime? now}) =>
      AccountSnapshot(
        equity: account.equity,
        balance: account.balance,
        dailyPnl: account.dailyPnl,
        peakEquity: account.peakEquity == 0
            ? account.initialBalance
            : account.peakEquity,
        asOf: now ?? DateTime.now(),
      );

  final double equity;
  final double balance;
  final double dailyPnl;
  final double peakEquity;
  final DateTime asOf;
}

abstract class AccountRepository {
  Future<List<TradingAccount>> fetchAccounts();

  Future<AccountSnapshot> fetchSnapshot(String accountId);

  Future<TradingAccount> createAccount(TradingAccount account);

  Future<void> deleteAccount(String accountId);

  Future<void> setEquityGuardEnabled(String accountId, bool enabled);

  /// Per-account copy permission (`broker_accounts.copy_enabled`, task 3.6).
  /// OFF by default: `evaluateAccount` refuses `accountDisabled` until the
  /// owner turns it on, so this switch is the only thing standing between a
  /// freshly connected account and a placed follow.
  Future<void> setCopyEnabled(String accountId, bool enabled);
}

/// In-memory accounts used in mock mode. Starts from the seeded demo accounts so the UI is
/// identical to what the tests assert on.
class MockAccountRepository implements AccountRepository {
  MockAccountRepository() : _accounts = MockData.accounts();

  final List<TradingAccount> _accounts;

  @override
  Future<List<TradingAccount>> fetchAccounts() async =>
      List<TradingAccount>.unmodifiable(_accounts);

  @override
  Future<AccountSnapshot> fetchSnapshot(String accountId) async {
    final TradingAccount? a = _byId(accountId);
    if (a == null) {
      throw StateError('Unknown account: $accountId');
    }
    return AccountSnapshot.fromAccount(a);
  }

  @override
  Future<TradingAccount> createAccount(TradingAccount account) async {
    if (_byId(account.id) != null) {
      throw StateError('Account already exists: ${account.id}');
    }
    _accounts.add(account);
    return account;
  }

  @override
  Future<void> deleteAccount(String accountId) async {
    _accounts.removeWhere((TradingAccount a) => a.id == accountId);
  }

  @override
  Future<void> setEquityGuardEnabled(String accountId, bool enabled) async {
    final int i = _indexOf(accountId);
    if (i < 0) throw StateError('Unknown account: $accountId');
    _accounts[i] = _copyWith(_accounts[i], equityGuardEnabled: enabled);
  }

  @override
  Future<void> setCopyEnabled(String accountId, bool enabled) async {
    final int i = _indexOf(accountId);
    if (i < 0) throw StateError('Unknown account: $accountId');
    _accounts[i] = _copyWith(_accounts[i], copyEnabled: enabled);
  }

  TradingAccount? _byId(String id) {
    final int i = _indexOf(id);
    return i < 0 ? null : _accounts[i];
  }

  int _indexOf(String id) =>
      _accounts.indexWhere((TradingAccount a) => a.id == id);

  /// Field-preserving copy. Every field must be carried explicitly: an
  /// omitted one would silently reset (this is also where a prior version
  /// dropped `metaapiAccountId`, unlinking the broker on every toggle — the
  /// copy toggle and the guard toggle share this path, so it is preserved
  /// here along with [copyEnabled]).
  static TradingAccount _copyWith(
    TradingAccount a, {
    bool? equityGuardEnabled,
    bool? copyEnabled,
  }) =>
      TradingAccount(
        id: a.id,
        nickname: a.nickname,
        platform: a.platform,
        phase: a.phase,
        currency: a.currency,
        initialBalance: a.initialBalance,
        profitTarget: a.profitTarget,
        dailyLossLimit: a.dailyLossLimit,
        maxDrawdown: a.maxDrawdown,
        drawdownType: a.drawdownType,
        equity: a.equity,
        balance: a.balance,
        dailyPnl: a.dailyPnl,
        peakEquity: a.peakEquity,
        propFirm: a.propFirm,
        metaapiAccountId: a.metaapiAccountId,
        equityGuardEnabled: equityGuardEnabled ?? a.equityGuardEnabled,
        copyEnabled: copyEnabled ?? a.copyEnabled,
      );
}
