import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/copy_settings.dart';
import '../models/guard_status.dart';
import '../models/live_account.dart';
import '../models/signal.dart';
import '../models/trade.dart';
import '../../features/journal/data/trade_screenshot_service.dart';
import '../../features/guard/data/live_account_repository.dart';
import '../../features/settings/data/delete_account_repository.dart';
import '../../features/journal/domain/trade_grade.dart';
import '../../features/journal/domain/trade_metrics.dart';
import '../../features/journal/domain/trade_review.dart';
import 'account_repository.dart';
import 'broker_connect_service.dart';
import 'copy_settings_repository.dart';
import 'guard_alert_monitor.dart';
import 'mock_data.dart';
import 'services.dart';
import 'telemetry_service.dart';
import 'trade_repository.dart';

import '../../features/paywall/data/purchase_repository.dart';

/// True when the app is running without a configured backend.
bool get kUseMock => Services.instance.isMock;

/// ---- Accounts ----

class AccountsNotifier extends StateNotifier<List<TradingAccount>> {
  AccountsNotifier(this._repo) : super(const <TradingAccount>[]) {
    unawaited(refresh());
  }

  final AccountRepository _repo;

  /// Non-null when the last load failed. The UI surfaces OFFLINE rather than showing
  /// stale-but-plausible numbers as if they were live.
  Object? _error;
  Object? get error => _error;

  /// True once the repository has answered at least once, successfully or not.
  ///
  /// [state] starts as an empty list, which on its own is ambiguous between "still
  /// loading" and "you have no accounts". Without this the Guard screen cannot tell
  /// a first load that is merely in flight from one that finished empty, and would
  /// spin a loading indicator forever after a failure.
  bool _loaded = false;
  bool get loaded => _loaded;

  TradingAccount? byId(String id) {
    for (final TradingAccount a in state) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> refresh() async {
    try {
      final List<TradingAccount> rows = await _repo.fetchAccounts();
      _error = null;
      _loaded = true;
      state = rows;
    } catch (e) {
      _error = e;
      // `loaded` and `error` are plain fields, not part of `state`, so nothing would
      // rebuild a screen still showing "loading". Publishing a fresh list gives the
      // notifier a new identity to emit, which is what wakes the listener — without
      // this a FIRST load that fails leaves the Guard screen spinning forever.
      _loaded = true;
      if (mounted) state = List<TradingAccount>.unmodifiable(state);
    }
  }

  Future<void> addAccount(TradingAccount a) async {
    await _repo.createAccount(a);
    await refresh();
  }

  Future<void> removeAccount(String accountId) async {
    await _repo.deleteAccount(accountId);
    await refresh();
  }

  Future<void> setEquityGuardEnabled(String accountId, bool enabled) async {
    await _repo.setEquityGuardEnabled(accountId, enabled);
    await refresh();
  }

  Future<void> setCopyEnabled(String accountId, bool enabled) async {
    await _repo.setCopyEnabled(accountId, enabled);
    await refresh();
  }
}

final StateNotifierProvider<AccountsNotifier, List<TradingAccount>> accountsProvider =
    StateNotifierProvider<AccountsNotifier, List<TradingAccount>>(
  (Ref ref) => AccountsNotifier(Services.instance.accounts),
);

/// Explicit user selection. `null` means "not chosen yet" — see [selectedAccountProvider].
final StateProvider<String?> selectedAccountIdProvider =
    StateProvider<String?>((Ref ref) => null);

/// The account the guard reports on. Falls back to the first account so the screen is never
/// "loaded but nothing selected", and never keeps a selection that a delete invalidated.
final Provider<TradingAccount?> selectedAccountProvider =
    Provider<TradingAccount?>((Ref ref) {
  final List<TradingAccount> accounts = ref.watch(accountsProvider);
  if (accounts.isEmpty) return null;
  final String? id = ref.watch(selectedAccountIdProvider);
  for (final TradingAccount a in accounts) {
    if (a.id == id) return a;
  }
  return accounts.first;
});

/// ---- Copy settings (task 3.6) ----
///
/// The trader's own `copy_settings` row: live consent, kill switch, max-lots
/// cap, concurrent cap. [CopySettingsNotifier] mirrors [AccountsNotifier]'s
/// shape (state = the row, `loadError` as a plain getter) with one deliberate
/// difference: saves are PESSIMISTIC. [state] advances only after the row has
/// been written, because every one of these values is a guardrail — a switch
/// that read "kill switch ON" while the write was still in flight (or had
/// failed) would be the app claiming a safety that does not exist server-side.
/// The UI's Switch is bound to [state], so on a failed save it simply never
/// moves, and the caller reports the failure.
class CopySettingsNotifier extends StateNotifier<CopySettings> {
  CopySettingsNotifier(this._repo) : super(CopySettings.defaults) {
    unawaited(refresh());
  }

  final CopySettingsRepository _repo;

  /// Non-null when the last LOAD failed. State then still holds whatever it
  /// held before (defaults on first load), and the Settings screen says so —
  /// showing defaults silently would read as "kill switch is OFF" when the
  /// stored row might say otherwise.
  Object? _loadError;
  Object? get loadError => _loadError;

  /// True while a save is in flight. Handlers check it before starting so two
  /// rapid taps cannot race two upserts of the same row.
  bool _saving = false;
  bool get saving => _saving;

  Future<void> refresh() async {
    try {
      state = await _repo.fetchCopySettings();
      _loadError = null;
    } catch (e) {
      _loadError = e;
    }
  }

  /// Writes [next] first and adopts it only on success. Returns whether the
  /// row now holds [next]; the raw error never leaves this method — the sheet
  /// and Settings screen phrase failures in their own words.
  Future<bool> _save(CopySettings next) async {
    if (_saving) return false;
    _saving = true;
    try {
      await _repo.saveCopySettings(next);
      state = next;
      _loadError = null;
      return true;
    } catch (_) {
      return false;
    } finally {
      _saving = false;
    }
  }

  Future<bool> setKillSwitch(bool value) =>
      _save(state.copyWith(killSwitch: value));

  Future<bool> setLiveConsent(bool value) =>
      _save(state.copyWith(liveConsent: value));

  Future<bool> setMaxLots(double value) =>
      _save(state.copyWith(maxLots: value));

  Future<bool> setMaxConcurrentFollows(int value) =>
      _save(state.copyWith(maxConcurrentFollows: value));
}

final StateNotifierProvider<CopySettingsNotifier, CopySettings>
copySettingsProvider =
    StateNotifierProvider<CopySettingsNotifier, CopySettings>(
  (Ref ref) => CopySettingsNotifier(Services.instance.copySettings),
);

// ---- Account deletion (store compliance) ----

/// The `delete-account` Edge Function, as a plain provider: the tree owns the
/// implementation, and swapping it is what makes the destructive confirmation
/// UI testable. In mock mode [Services.instance.deleteAccount] records the
/// request and resolves without touching anything, so the confirm gating, the
/// sign-out on success and the trader-safe error copy are all exercisable with
/// no backend — nothing is ever really deleted in mock mode.
final Provider<DeleteAccountRepository> deleteAccountRepositoryProvider =
    Provider<DeleteAccountRepository>((Ref ref) => Services.instance.deleteAccount);

// ---- Purchases (Flutterwave premium toggle) ----

/// UI state exposed by [PurchaseNotifier].
///
/// [isPro] mirrors `profiles.is_premium`; [isLoading] is true while the flag is
/// being (re)read; [error] carries the last failure, mapped to a trader-safe
/// [PurchaseFailure] by the repository.
class PurchaseState {
  final bool isPro;
  final bool isLoading;
  final Object? error;
  const PurchaseState({
    required this.isPro,
    this.isLoading = false,
    this.error,
  });

  PurchaseState copyWith({
    bool? isPro,
    bool? isLoading,
    Object? error,
  }) =>
      PurchaseState(
        isPro: isPro ?? this.isPro,
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
      );
}

/// Thin Riverpod notifier over [PurchaseRepository]. State is the premium flag
/// and any load error; the underlying repository reads `profiles.is_premium`
/// from Supabase. [refresh] is called once on construction so every Pro gate
/// reads the real status, and again when the paywall's "Check Status" button is
/// tapped after the trader returns from the Flutterwave page.
class PurchaseNotifier extends StateNotifier<PurchaseState> {
  PurchaseNotifier(this._repo)
      : super(const PurchaseState(isPro: false, isLoading: true)) {
    refresh();
  }

  final PurchaseRepository _repo;

  /// Re-reads the premium flag from `profiles.is_premium`. Sets
  /// [PurchaseState.isLoading] while the request is in flight and records any
  /// failure on [PurchaseState.error] as a trader-safe message.
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    try {
      final bool isPro = await _repo.isPro();
      // Segment crash reports by tier. 'free'/'pro' only — never an account id,
      // email or receipt.
      TelemetryService.instance.setAppTier(isPro ? 'pro' : 'free');
      state = state.copyWith(isPro: isPro, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    }
  }

  /// Proxy to the underlying repository stream.
  Stream<bool> watchProStatus() => _repo.watchProStatus();
}


/// The single place that chooses mock vs live and hands the notifier its
/// repository: [Services.instance.purchases] is `MockPurchaseRepository()` in
/// mock mode and `SupabasePurchaseRepository()` otherwise (see
/// [Services.purchases]), so the UI can run fully offline until keys exist.
final StateNotifierProvider<PurchaseNotifier, PurchaseState>
purchasesProvider =
    StateNotifierProvider<PurchaseNotifier, PurchaseState>(
  (Ref ref) => PurchaseNotifier(Services.instance.purchases),
);

/// ---- Broker connect ----

/// Where the connect flow currently is. Keeping this as an explicit state (rather than a local
/// `bool isBusy`) is what lets the sheet survive a rebuild mid-request without double-submitting.
enum ConnectStatus { idle, connecting, success, failure }

class ConnectState {
  const ConnectState({
    this.status = ConnectStatus.idle,
    this.message,
  });

  const ConnectState.idle() : this();

  final ConnectStatus status;
  final String? message;

  bool get isBusy => status == ConnectStatus.connecting;
}

/// Drives `meta-connect` then persists the account through [AccountsNotifier].
///
/// The broker password lives only in the [BrokerConnectionRequest] the sheet builds; it is passed
/// straight through to the Edge Function and is not part of [ConnectState], so it cannot leak into
/// the widget tree, a log, or persisted state.
class ConnectAccountNotifier extends StateNotifier<ConnectState> {
  ConnectAccountNotifier(this._connect, this._accounts)
      : super(const ConnectState.idle());

  final BrokerConnectService _connect;
  final AccountsNotifier _accounts;

  bool get isStubbed => _connect.isStubbed;

  /// Returns the new account id, or null on failure (with [ConnectState.message] set).
  Future<String?> connect(BrokerConnectionRequest request) async {
    final Map<String, String> errors = validateConnection(request);
    if (errors.isNotEmpty) {
      state = ConnectState(
        status: ConnectStatus.failure,
        message: errors.values.first,
      );
      return null;
    }

    state = const ConnectState(status: ConnectStatus.connecting);

    try {
      final String metaapiAccountId = await _connect.connectBroker(request);
      await _accounts.addAccount(connectedAccount(request, metaapiAccountId));
      state = ConnectState(
        status: ConnectStatus.success,
        message: '${request.nickname.trim()} connected.',
      );
      return metaapiAccountId;
    } on BrokerConnectException catch (e) {
      state = ConnectState(status: ConnectStatus.failure, message: e.message);
      return null;
    } catch (_) {
      // Never surface a raw platform error string — it can contain the broker response body.
      state = const ConnectState(
        status: ConnectStatus.failure,
        message: 'Could not connect that account. Try again shortly.',
      );
      return null;
    }
  }

  void reset() => state = const ConnectState.idle();
}

final StateNotifierProvider<ConnectAccountNotifier, ConnectState>
    connectAccountProvider =
    StateNotifierProvider<ConnectAccountNotifier, ConnectState>(
  (Ref ref) => ConnectAccountNotifier(
    Services.instance.brokerConnect,
    ref.read(accountsProvider.notifier),
  ),
);

/// ---- Guard ----

/// Fires at most one push per loss-threshold crossing as guard readings change.
final Provider<GuardAlertMonitor> guardAlertMonitorProvider =
    Provider<GuardAlertMonitor>(
  (Ref ref) => GuardAlertMonitor(push: Services.instance.push),
);

final Provider<GuardStatus?> guardStatusProvider = Provider<GuardStatus?>((Ref ref) {
  final TradingAccount? account = ref.watch(selectedAccountProvider);
  if (account == null) return null;
  return GuardStatus.compute(account);
});

/// ---- Live account (balance, equity, open positions) ----

/// The `LiveAccountRepository` seam: mock in demo mode, Supabase/Edge Function
/// otherwise. Overridable in widget tests with a seeded fake.
final Provider<LiveAccountRepository> liveAccountRepositoryProvider =
    Provider<LiveAccountRepository>((Ref ref) => Services.instance.liveAccounts);

/// Live account data for one account id.
///
/// A [FutureProvider.family] rather than a value on the accounts notifier, so a
/// slow or failed live read can NEVER block or corrupt the guard math: the
/// dashboard renders this in its own loading/error/empty states while the guard
/// cards below keep rendering from the persisted account. [autoDispose] frees the
/// snapshot when the trader switches tabs or accounts.
final AutoDisposeFutureProviderFamily<LiveAccountData, String> liveAccountProvider =
    FutureProvider.autoDispose.family<LiveAccountData, String>((Ref ref, String accountId) {
  return ref.watch(liveAccountRepositoryProvider).fetchLive(accountId);
});

/// ---- Trades ----

/// Screenshot bytes for the journal (task 2.3). Mock mode keeps bytes in
/// memory; live mode uses the private `trade-screenshots` bucket.
/// Overridable in widget tests with a seeded fake.
final Provider<TradeScreenshotService> tradeScreenshotServiceProvider =
    Provider<TradeScreenshotService>(
  (Ref ref) => Services.instance.screenshots,
);

final StateNotifierProvider<TradesNotifier, List<Trade>> tradesProvider =
    StateNotifierProvider<TradesNotifier, List<Trade>>(
  (Ref ref) => TradesNotifier(
    Services.instance.trades,
    screenshots: ref.watch(tradeScreenshotServiceProvider),
  ),
);

class TradesNotifier extends StateNotifier<List<Trade>> {
  TradesNotifier(this._repo, {TradeScreenshotService? screenshots})
      : _screenshots = screenshots ?? Services.instance.screenshots,
        super(const <Trade>[]) {
    unawaited(refresh());
  }

  final TradeRepository _repo;
  final TradeScreenshotService _screenshots;

  Object? _error;
  Object? get error => _error;

  /// True once the repository has answered at least once, successfully or not.
  ///
  /// [state] starts as an empty list, which on its own is ambiguous between "still loading" and
  /// "you have no trades". Without this the Journal would flash a misleading empty state on
  /// every cold start, which is exactly the moment a trader is least likely to trust it.
  bool _loaded = false;
  bool get loaded => _loaded;

  List<Trade> forAccount(String? accountId) => accountId == null
      ? state
      : state.where((Trade t) => t.accountId == accountId).toList();

  Future<void> refresh() async {
    try {
      final List<Trade> rows = await _repo.fetchTrades();
      _error = null;
      state = rows;
      _loaded = true;
    } catch (e) {
      _error = e;
      // `loaded` and `error` are plain fields, not part of `state`, so nothing would rebuild a
      // screen that is still showing "loading". Writing a fresh list gives the notifier a new
      // identity to publish, which is what actually wakes the listener — without this, a FIRST
      // load that fails leaves the Journal spinning forever.
      if (mounted) state = List<Trade>.unmodifiable(state);
      _loaded = true;
    }
  }

  /// Persists through the repository (mock in-memory, Supabase in live mode) and re-reads, so
  /// the journal never shows an optimistic value the backend rejected.
  Future<void> updateGrade(String tradeId, String grade) async {
    await _repo.updateGrade(tradeId, grade);
    await refresh();
  }

  Future<void> updateNotes(String tradeId, String notes) async {
    await _repo.updateNotes(tradeId, notes);
    await refresh();
  }

  /// Uploads [picked] to the private screenshot bucket and links the returned
  /// storage path to the trade, then re-reads so the screen shows the bytes
  /// the backend accepted — never an optimistic local value.
  Future<void> uploadScreenshot(
    String tradeId,
    PickedScreenshot picked,
  ) async {
    final String path = await _screenshots.upload(
      tradeId: tradeId,
      bytes: picked.bytes,
      fileName: picked.fileName,
      mimeType: picked.mimeType,
    );
    await _repo.updateScreenshot(tradeId, path);
    await refresh();
  }

  /// The trade with [tradeId], or null.
  ///
  /// Resolution always goes through this repository-scoped list, never through an id supplied
  /// straight to a query: the repository is where RLS scopes rows to the signed-in user, so a
  /// trade belonging to another account simply is not in [state].
  Trade? byId(String tradeId) {
    for (final Trade t in state) {
      if (t.id == tradeId) return t;
    }
    return null;
  }
}

/// Screenshot bytes for one linked storage path (task 2.3).
///
/// A family keyed on the path, so a re-upload (which links a NEW path)
/// cannot flash the previous image. Null/empty paths answer null without
/// touching storage.
final FutureProviderFamily<Uint8List?, String> tradeScreenshotBytesProvider =
    FutureProvider.family<Uint8List?, String>((
  Ref ref,
  String path,
) {
  if (path.isEmpty) return Future<Uint8List?>.value();
  return ref.watch(tradeScreenshotServiceProvider).download(path);
});

/// ---- Signals (task 3.1) ----
///
/// The feed behind `signalFeedProvider` in `features/signals`. Kept here (not
/// moved into the feature) because the copy-confirm sheet in
/// `features/signals/presentation` already imports from this file, and moving
/// it would churn every import for no behavioural gain.
final Provider<List<Signal>> signalsProvider = Provider<List<Signal>>((Ref ref) {
  // Legacy alias: the screen reads `signalFeedProvider` directly, but older
  // widgets and tests may still watch this. In demo mode it mirrors the same
  // seed the mock repository serves, so both paths can never disagree. In live
  // mode it must stay EMPTY: `MockData` is seeded demo content, and handing it
  // to a live widget would show a real trader fabricated operator signals.
  return kUseMock ? MockData.signals() : const <Signal>[];
});

/// ---- Trade review (task 2.3) ----

/// Deterministic metrics for one trade.
///
/// Returns null when the trade is not in [tradesProvider], so a screen can distinguish "not
/// found / not yours" from "found".
final ProviderFamily<TradeMetrics?, String> tradeMetricsProvider =
    Provider.family<TradeMetrics?, String>((Ref ref, String tradeId) {
  final Trade? trade = ref.watch(tradesProvider.notifier).byId(tradeId);
  if (trade == null) return null;
  return TradeMetrics.of(trade);
});

/// The grade + reasons for one trade.
///
/// A hand-set `trades.grade` wins over the derived one: the trader is the authority on their own
/// execution, and the spec has always let them pick A–D by hand.
final ProviderFamily<TradeReview?, String> tradeReviewProvider =
    Provider.family<TradeReview?, String>((Ref ref, String tradeId) {
  final TradeMetrics? metrics = ref.watch(tradeMetricsProvider(tradeId));
  if (metrics == null) return null;
  final TradeReview derived = TradeReview.of(metrics);
  final TradeGrade? manual = TradeGrade.tryParse(metrics.trade.grade);
  if (manual == null) return derived;
  return TradeReview(
    metrics: derived.metrics,
    grade: manual,
    reasons: derived.reasons,
  );
});

/// ---- Journal stats ----

class JournalStats {
  const JournalStats({
    required this.netPnl,
    required this.winRate,
    required this.profitFactor,
    required this.avgR,
    required this.count,
  });

  final double netPnl;
  final double winRate;
  final double profitFactor;
  final double avgR;
  final int count;
}

final Provider<JournalStats> journalStatsProvider = Provider<JournalStats>((Ref ref) {
  final List<Trade> trades = ref.watch(tradesProvider);
  final double net = trades.fold<double>(0, (double s, Trade t) => s + t.pnl);
  final int wins = trades.where((Trade t) => t.pnl > 0).length;
  final double grossWin =
      trades.where((Trade t) => t.pnl > 0).fold<double>(0, (double s, Trade t) => s + t.pnl);
  final double grossLoss =
      trades.where((Trade t) => t.pnl < 0).fold<double>(0, (double s, Trade t) => s + t.pnl.abs());
  final double avgR = trades.isEmpty
      ? 0
      : trades.fold<double>(0, (double s, Trade t) => s + (t.rMultiple ?? 0)) / trades.length;
  return JournalStats(
    netPnl: net,
    winRate: trades.isEmpty ? 0 : (wins / trades.length) * 100,
    profitFactor: grossLoss == 0 ? 0 : grossWin / grossLoss,
    avgR: avgR,
    count: trades.length,
  );
});
