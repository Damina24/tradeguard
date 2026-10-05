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
  /// ⚠️ SERVER-SIDE ONLY — MUST STAY EMPTY IN EVERY `env/*.json` BUILD.
  ///
  /// TwelveData is a metered per-key credential. Anything passed via `--dart-define` is compiled
  /// into the binary, so a value here ships inside the APK/AAB and anyone who installs the app can
  /// extract it and spend our allowance from outside the product. The key belongs in
  /// `supabase secrets` and is read only by the `market-bars` Edge Function.
  ///
  /// Nothing reads this field: the client never calls TwelveData, because
  /// `SupabasePriceBarRepository` fetches through `market-bars` instead. It is retained as a declared
  /// placeholder so the config schema stays uniform across services and so an accidental
  /// `TWELVEDATA_KEY` in an env file is visible here rather than silently ignored. Do NOT "wire it
  /// up" — the allowlist and normalisation in `market-bars` are deliberate server-side policy.
  /// See `docs/BACKEND_DEPLOY.md` step 3 and task 2.6 in `docs/IMPLEMENTATION_PLAN.md`.
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
