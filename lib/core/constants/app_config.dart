/// Build-time configuration. Values come from `--dart-define-from-file`.
/// When [supabaseUrl] is empty the app runs in MOCK mode (no backend needed).
class AppConfig {
  AppConfig._();

  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  static const String metaApiToken =
      String.fromEnvironment('METAAPI_TOKEN', defaultValue: '');
  static const String openAiKey =
      String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
  static const String revenueCatIosKey =
      String.fromEnvironment('REVENUECAT_IOS_KEY', defaultValue: '');
  static const String revenueCatAndroidKey =
      String.fromEnvironment('REVENUECAT_ANDROID_KEY', defaultValue: '');
  static const String twelveDataKey =
      String.fromEnvironment('TWELVEDATA_KEY', defaultValue: '');

  // --- Social sign-in (Apple / Google) -------------------------------------
  // All three are OPTIONAL: without them the social buttons report "not configured for this build"
  // instead of crashing, and email + password keeps working.

  /// iOS Google client id (`GoogleService-Info.plist` holds this on Android).
  static const String googleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID', defaultValue: '');

  /// Google *web* client id. Required on Android, where the plugin needs it to mint an id token
  /// that Supabase will accept.
  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '');

  /// Apple Service ID (`com.tradeguard.app.web`). Only used on Android, which runs the Apple flow
  /// in a browser tab and therefore needs an explicit client id + redirect.
  static const String appleWebClientId =
      String.fromEnvironment('APPLE_WEB_CLIENT_ID', defaultValue: '');

  static const String supportEmail = 'support@__PLACEHOLDER_DOMAIN__';
  static const String privacyUrl = 'https://__PLACEHOLDER_DOMAIN__/privacy';
  static const String termsUrl = 'https://__PLACEHOLDER_DOMAIN__/terms';
  static const String deleteAccountUrl =
      'https://__PLACEHOLDER_DOMAIN__/delete-account';

  /// True when no real backend is configured.
  static bool get useMock => supabaseUrl.isEmpty;
}
