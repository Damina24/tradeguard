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

  static const String supportEmail = 'support@__PLACEHOLDER_DOMAIN__';
  static const String privacyUrl = 'https://__PLACEHOLDER_DOMAIN__/privacy';
  static const String termsUrl = 'https://__PLACEHOLDER_DOMAIN__/terms';
  static const String deleteAccountUrl =
      'https://__PLACEHOLDER_DOMAIN__/delete-account';

  /// True when no real backend is configured.
  static bool get useMock => supabaseUrl.isEmpty;
}
