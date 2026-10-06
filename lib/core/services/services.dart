import '../constants/app_config.dart';
import '../../features/ai_review/data/ai_review_repository.dart';
import '../../features/ai_review/data/mock_ai_review_repository.dart';
import '../../features/ai_review/data/supabase_ai_review_repository.dart';
import '../../features/patterns/data/mock_pattern_repository.dart';
import '../../features/patterns/data/pattern_repository.dart';
import '../../features/patterns/data/supabase_pattern_repository.dart';
import '../../features/replay/data/mock_price_bar_repository.dart';
import '../../features/replay/data/price_bar_repository.dart';
import '../../features/replay/data/supabase_price_bar_repository.dart';
import '../../features/signals/data/mock_signal_repository.dart';
import '../../features/signals/data/signal_repository.dart';
import '../../features/signals/data/supabase_signal_repository.dart';
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

  /// Mock mode produces reviews offline from the deterministic checklist, so the AI Review card is
  /// fully exercisable with no `OPENAI_API_KEY`.
  late final AiReviewRepository aiReviews = isMock
      ? MockAiReviewRepository()
      : SupabaseAiReviewRepository();

  /// OHLC bars for the replay (task 2.6). Mock mode generates a deterministic walk per symbol, so the
  /// replay screen — including the scan and its bar-by-bar controls — is exercisable with no backend
  /// and no `TWELVEDATA_KEY`. The mock labels its own output `SYNTHETIC DEMO` on the chart, because an
  /// unlabelled generated chart is indistinguishable from the market.
  late final PriceBarRepository prices = isMock
      ? MockPriceBarRepository()
      : SupabasePriceBarRepository();

  /// Operator-posted signals (task 3.1). Mock mode returns the same fixture
  /// shape the live table returns, so the feed and the verified stats are
  /// fully exercisable with no backend and no credentials. The mock labels
  /// its own output `OFFLINE DEMO` on the screen, because an unlabelled demo
  /// feed is indistinguishable from live operator posts.
  late final SignalRepository signals = isMock
      ? MockSignalRepository()
      : SupabaseSignalRepository();

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
