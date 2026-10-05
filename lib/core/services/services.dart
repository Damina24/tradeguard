import '../constants/app_config.dart';
import '../../features/patterns/data/mock_pattern_repository.dart';
import '../../features/patterns/data/pattern_repository.dart';
import '../../features/patterns/data/supabase_pattern_repository.dart';
import 'account_repository.dart';
import 'auth_repository.dart';
import 'broker_connect_service.dart';
import 'fcm_push_service.dart';
import 'push_service.dart';
import 'supabase_account_repository.dart';
import 'supabase_auth_repository.dart';
import 'supabase_service.dart';
import 'supabase_trade_repository.dart';
import 'trade_repository.dart';

/// Single place that decides whether the app talks to Supabase or to the in-memory mocks.
///
/// [AppConfig.useMock] is true whenever `SUPABASE_URL` is empty, so an unconfigured checkout
/// boots with demo data and never throws.
class Services {
  Services._();

  static final Services instance = Services._();

  /// True when running against the offline mocks.
  bool get isMock => AppConfig.useMock;

  late final AuthRepository auth = isMock
      ? MockAuthRepository()
      : SupabaseAuthRepository();

  late final AccountRepository accounts = isMock
      ? MockAccountRepository()
      : SupabaseAccountRepository();

  late final TradeRepository trades = isMock
      ? MockTradeRepository()
      : SupabaseTradeRepository();

  /// `v_patterns` rows for the signed-in trader. Mock mode returns the same
  /// pre-grouped fixture shape the live view returns, so the pattern views and
  /// the leaks screen are fully exercisable with no backend and no credentials.
  late final PatternRepository patterns = isMock
      ? MockPatternRepository()
      : SupabasePatternRepository();

  /// Registers a broker account with MetaAPI. Mock mode fabricates the id so the connect flow is
  /// usable before a `METAAPI_TOKEN` exists.
  late final BrokerConnectService brokerConnect = isMock
      ? MockBrokerConnectService()
      : SupabaseBrokerConnectService();

  /// Mock mode records alerts instead of showing them, so the threshold flow stays testable and
  /// nothing pretends to notify when there is no Firebase project yet.
  late final PushService push = isMock ? MockPushService() : FcmPushService();

  /// Boots the Supabase client. Safe to call in mock mode (it is a no-op there).
  Future<void> init() => SupabaseService.instance.init();
}
