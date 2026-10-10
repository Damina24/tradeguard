import '../models/account.dart';
import 'supabase_service.dart';

/// The credentials and prop rules the user typed on the connect sheet.
///
/// [password] is the ONLY broker secret that ever exists in the app. It is held in memory for the
/// duration of one request, relayed to the `meta-connect` Edge Function, and then discarded: it is
/// never written to disk, to Postgres, to a log line or to analytics. What we keep is the opaque
/// `metaapi_account_id` returned by the call.
class BrokerConnectionRequest {
  const BrokerConnectionRequest({
    required this.login,
    required this.password,
    required this.server,
    required this.platform,
    required this.nickname,
    required this.phase,
    required this.currency,
    required this.initialBalance,
    required this.profitTarget,
    required this.dailyLossLimit,
    required this.maxDrawdown,
    required this.drawdownType,
    this.propFirm,
    this.enableEquityGuard = true,
  });

  /// Broker investor id. MetaAPI requires a numeric login.
  final String login;
  final String password;
  final String server;

  /// `mt4` | `mt5` | `ctrader`.
  final String platform;

  final String nickname;
  final AccountPhase phase;
  final String currency;
  final double initialBalance;
  final double profitTarget;
  final double dailyLossLimit;
  final double maxDrawdown;
  final DrawdownType drawdownType;
  final String? propFirm;
  final bool enableEquityGuard;

  /// Platforms MetaAPI provisions. Kept here (not only in the UI) so the Edge Function payload and
  /// the dropdown can never drift apart.
  static const List<String> platforms = <String>['mt5', 'mt4', 'ctrader'];

  /// Wire format for the `meta-connect` Edge Function. Note the absence of any account number,
  /// equity or guard state — this call only registers the broker connection.
  Map<String, dynamic> toFunctionBody() => <String, dynamic>{
        'login': login,
        'password': password,
        'server': server,
        'platform': platform,
      };
}

/// Broker connect failed. The message is safe to show the user — no credential ever echoes back.
class BrokerConnectException implements Exception {
  const BrokerConnectException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Validation shared by the connect sheet and the unit tests: pure, no Flutter, no plugin channels.
///
/// Returns a map of field -> message. An empty map means the request is good to send.
Map<String, String> validateConnection(BrokerConnectionRequest r) {
  final Map<String, String> errors = <String, String>{};

  if (r.login.trim().isEmpty) {
    errors['login'] = 'Enter your broker account number.';
  } else if (!RegExp(r'^\d+$').hasMatch(r.login.trim())) {
    errors['login'] = 'Account number must be digits only.';
  }

  if (r.password.isEmpty) {
    errors['password'] = 'Enter your broker password.';
  }

  if (r.server.trim().isEmpty) {
    errors['server'] = 'Enter the broker server name.';
  }

  if (!BrokerConnectionRequest.platforms.contains(r.platform)) {
    errors['platform'] = 'Choose a supported platform.';
  }

  if (r.nickname.trim().isEmpty) {
    errors['nickname'] = 'Give the account a nickname.';
  }

  if (r.initialBalance <= 0) {
    errors['initialBalance'] = 'Initial balance must be greater than zero.';
  }

  if (r.profitTarget <= 0) {
    errors['profitTarget'] = 'Profit target must be greater than zero.';
  }

  if (r.dailyLossLimit <= 0) {
    errors['dailyLossLimit'] = 'Daily loss limit must be greater than zero.';
  }

  if (r.maxDrawdown <= 0) {
    errors['maxDrawdown'] = 'Max drawdown must be greater than zero.';
  }

  return errors;
}


/// Turns a validated request plus the returned MetaAPI id into the row the app persists.
///
/// Live numbers deliberately start at the initial balance rather than being invented: `guard-check`
/// writes the first real `equity_snapshots` row within a minute, and until then the Guard screen
/// degrades to STALE instead of showing a fabricated P&L.
TradingAccount connectedAccount(
  BrokerConnectionRequest r,
  String metaapiAccountId, {
  DateTime? now,
}) =>
    TradingAccount(
      id: 'acc_${(now ?? DateTime.now()).millisecondsSinceEpoch}',
      nickname: r.nickname.trim(),
      platform: r.platform,
      phase: r.phase,
      currency: r.currency,
      initialBalance: r.initialBalance,
      profitTarget: r.profitTarget,
      dailyLossLimit: r.dailyLossLimit,
      maxDrawdown: r.maxDrawdown,
      drawdownType: r.drawdownType,
      equity: r.initialBalance,
      balance: r.initialBalance,
      dailyPnl: 0,
      peakEquity: r.initialBalance,
      propFirm: r.propFirm,
      metaapiAccountId: metaapiAccountId,
      equityGuardEnabled: r.enableEquityGuard,
    );

/// Registers a broker account and hands back the MetaAPI id. Implementations MUST NOT persist or log
/// the password — the Edge Function relays it to MetaAPI and drops it.
abstract class BrokerConnectService {
  /// True when this service fakes the MetaAPI call (no `METAAPI_TOKEN` yet), so the UI can say so.
  bool get isStubbed;

  Future<String> connectBroker(BrokerConnectionRequest request);
}

/// Offline implementation. Returns a deterministic id so widget tests and screenshots stay stable.
class MockBrokerConnectService implements BrokerConnectService {
  MockBrokerConnectService({this.latency = const Duration(milliseconds: 250)});

  final Duration latency;

  /// Requests seen by this instance. The password is deliberately NOT recorded — the mock keeps
  /// only the non-secret fields, so a test can assert what was sent without holding the secret.
  final List<Map<String, dynamic>> receivedBodies = <Map<String, dynamic>>[];

  @override
  bool get isStubbed => true;

  @override
  Future<String> connectBroker(BrokerConnectionRequest request) async {
    final Map<String, String> errors = validateConnection(request);
    if (errors.isNotEmpty) {
      throw BrokerConnectException(errors.values.first);
    }
    await Future<void>.delayed(latency);
    final Map<String, dynamic> body = request.toFunctionBody();
    body.remove('password');
    receivedBodies.add(body);
    return 'mock_meta_${request.login.trim()}';
  }
}

/// Live implementation: POSTs to the `meta-connect` Edge Function over the Supabase Functions API.
class SupabaseBrokerConnectService implements BrokerConnectService {
  SupabaseBrokerConnectService([SupabaseService? service])
      : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  @override
  bool get isStubbed => false;

  @override
  Future<String> connectBroker(BrokerConnectionRequest request) async {
    final Map<String, String> errors = validateConnection(request);
    if (errors.isNotEmpty) {
      throw BrokerConnectException(errors.values.first);
    }

    // `FunctionsClient.invoke` throws on a non-2xx, so a transport/HTTP failure lands in the
    // catch below. The generic catch is deliberate: it must not be allowed to leak the upstream
    // response body (which can quote the broker login) into a user-visible string.
    final dynamic response;
    try {
      response = await _service.client.functions.invoke(
        'meta-connect',
        body: request.toFunctionBody(),
      ).timeout(SupabaseService.networkTimeout);
    } catch (_) {
      throw const BrokerConnectException(
        'Could not reach the broker connect service. Try again shortly.',
      );
    }

    final Object? data = response.data as Object?;
    if (data is! Map<String, dynamic>) {
      throw const BrokerConnectException(
        'The broker connect service returned an unexpected response.',
      );
    }

    // Deliberately not echoing the upstream message: a provider error can quote the login back.
    if (data['ok'] != true) {
      throw const BrokerConnectException(
        'The broker rejected those details. Check the account number, password and server.',
      );
    }

    final Object? id = data['metaapi_account_id'];
    if (id is! String || id.isEmpty) {
      throw const BrokerConnectException(
        'The broker connect service did not return an account id.',
      );
    }
    return id;
  }
}

