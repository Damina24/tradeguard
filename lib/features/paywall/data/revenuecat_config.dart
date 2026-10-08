import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

/// Build-time configuration for the RevenueCat store keys.
///
/// Keys are injected through `--dart-define` flags on the build command:
///   --dart-define=REVENUECAT_APPLE_KEY=<appl_...>   (iOS)
///   --dart-define=REVENUECAT_GOOGLE_KEY=<goog_...>  (Android)
///
/// Empty-string defaults are intentional and correct: a build that ships with
/// no store keys must never attempt to touch the store, and must instead fall
/// back to the offline/mock purchase behaviour. [isConfigured] is the sole
/// gate the repository consults before touching the store SDK.
class RevenueCatConfig {
  const RevenueCatConfig._();

  static const appleKey = String.fromEnvironment('REVENUECAT_APPLE_KEY');
  static const googleKey = String.fromEnvironment('REVENUECAT_GOOGLE_KEY');

  /// The entitlement identifier that gates "Pro" access.
  static const entitlementId = 'pro';

  /// The store key for the current platform.
  ///
  /// Simplest option, recorded per task rules: Android uses the Google Play
  /// key; every other platform (iOS today; web/desktop as a harmless fallback)
  /// uses the Apple key. RevenueCat keys are prefixed `goog_` / `appl_`
  /// respectively.
  static String get platformKey =>
      defaultTargetPlatform == TargetPlatform.android ? googleKey : appleKey;

  /// True only when the current platform's key is non-empty.
  static bool get isConfigured => platformKey.isNotEmpty;
}
