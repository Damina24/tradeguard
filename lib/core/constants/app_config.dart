import 'package:flutter/foundation.dart' show kReleaseMode;

/// Build-time configuration. Values come from `--dart-define-from-file`.
///
/// ## Mode selection
///
/// Demo ("mock") mode is **opt-in**, never a silent fallback:
///
///   * `--dart-define=USE_MOCK=true` → demo mode, in *any* build flavour. This is
///     the flag sales demos use, and the only way to get seeded data into a
///     release build on purpose.
///   * Release with no `USE_MOCK` → **never** demo. With `SUPABASE_URL` /
///     `SUPABASE_ANON_KEY` present it runs live; with them missing it shows the
///     fatal configuration screen instead of demo data (see [configMissing]).
///   * Debug/profile with no `USE_MOCK` and no `SUPABASE_URL` → demo mode, which
///     is the long-standing behaviour that lets the whole UI run with no keys.
///
/// `USE_MOCK` is the pre-existing define name (it already appears in every
/// `env/*.json`); it is now actually read instead of being a dead key.
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
  /// ⚠️ DEAD KEYS — nothing reads these. The RevenueCat keys actually wired into
  /// [RevenueCatConfig] are `REVENUECAT_APPLE_KEY` and `REVENUECAT_GOOGLE_KEY`;
  /// see `features/paywall/data/revenuecat_config.dart` and
  /// `docs/BACKEND_DEPLOY.md` §7 for the canonical release commands.
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

  /// Support inbox shown on the live legal pages. Kept for parity with the
  /// store listing; the in-app delete flow never needs it (it deletes directly).
  static const String supportEmail = 'support@tradeguard.app';

  /// Live, hosted legal pages (GitHub Pages, repo `Damina24/tradeguard-legal`).
  ///
  /// These are the ONLY public URLs a store reviewer or trader is pointed at, so
  /// they must resolve. The privacy policy and account-deletion pages are live;
  /// the terms page is not yet published on that host, so the Terms link falls
  /// back to the same legal home page (which carries the effective date, contact
  /// and the financial disclaimer) rather than to a 404. Update [termsUrl] to a
  /// dedicated `…/terms` page the moment one is published — see the widget test
  /// `legal_links_test.dart`, which pins the exact privacy/deletion URLs.
  static const String privacyUrl = 'https://damina24.github.io/tradeguard-legal/';
  static const String termsUrl = 'https://damina24.github.io/tradeguard-legal/';
  static const String deleteAccountUrl =
      'https://damina24.github.io/tradeguard-legal/account-deletion';

  /// Explicit request for demo/mock mode: `--dart-define=USE_MOCK=true`.
  ///
  /// This is the *only* thing that may turn mock mode on in a release build. It
  /// is already the name used by every `env/*.json`, so no second define is
  /// introduced here.
  static const bool mockModeRequested =
      bool.fromEnvironment('USE_MOCK', defaultValue: false);

  /// True when both halves of the Supabase client config are present.
  ///
  /// Both are required: a URL with no anon key cannot authenticate, and an anon
  /// key with no URL has nowhere to send it. Either one alone is not a
  /// configuration.
  static bool get hasSupabaseConfig =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  /// True for `--release` builds only (not profile).
  static bool get isReleaseBuild => kReleaseMode;

  /// Pure mode selection, extracted so the rule is unit-testable without
  /// compiling a second flavour of the app.
  ///
  ///   * An explicit `USE_MOCK=true` always wins — a demo build is a deliberate
  ///     build, and the flag must work identically in every flavour.
  ///   * A **release** build never falls back to demo data on its own.
  ///   * Debug/profile keep the original behaviour: no backend configured means
  ///     run the seeded mocks, so `flutter run` works with no keys at all.
  static bool resolveUseMock({
    required bool mockRequested,
    required bool hasSupabaseConfig,
    required bool isRelease,
  }) {
    if (mockRequested) return true;
    if (isRelease) return false;
    return !hasSupabaseConfig;
  }

  /// Pure fatal-configuration rule: a release build that neither asked for demo
  /// mode nor carries a usable Supabase config must stop, not show demo data.
  static bool resolveConfigMissing({
    required bool mockRequested,
    required bool hasSupabaseConfig,
    required bool isRelease,
  }) =>
      isRelease && !mockRequested && !hasSupabaseConfig;

  /// True when running against the offline mocks. See [resolveUseMock].
  static bool get useMock => resolveUseMock(
        mockRequested: mockModeRequested,
        hasSupabaseConfig: hasSupabaseConfig,
        isRelease: isReleaseBuild,
      );

  /// True when this build must show the fatal configuration screen instead of
  /// starting the app. Only reachable in release builds.
  static bool get configMissing => resolveConfigMissing(
        mockRequested: mockModeRequested,
        hasSupabaseConfig: hasSupabaseConfig,
        isRelease: isReleaseBuild,
      );

  /// Human-readable list of what is missing, for the fatal screen. Empty when
  /// nothing is missing.
  static List<String> get missingConfigKeys {
    final List<String> missing = <String>[];
    if (supabaseUrl.trim().isEmpty) missing.add('SUPABASE_URL');
    if (supabaseAnonKey.trim().isEmpty) missing.add('SUPABASE_ANON_KEY');
    return missing;
  }
}
