import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// The single analytics call the telemetry seam needs. An indirection so the
/// helper can be unit-tested with a fake, without a Firebase platform channel.
abstract class AnalyticsLogger {
  Future<void> logEvent(String name, Map<String, Object>? parameters);
}

/// Adapts the real [FirebaseAnalytics] singleton to [AnalyticsLogger].
class _FirebaseAnalyticsLogger implements AnalyticsLogger {
  _FirebaseAnalyticsLogger(this._analytics);

  final FirebaseAnalytics _analytics;

  @override
  Future<void> logEvent(String name, Map<String, Object>? parameters) {
    return _analytics.logEvent(name: name, parameters: parameters);
  }
}

/// A PII-safe telemetry seam over Firebase Analytics + Crashlytics.
///
/// Every method is best-effort and never throws: a build with no Firebase
/// config (mock mode, web, tests) must degrade telemetry, never the app — the
/// same contract `FcmPushService` already honours. Callers log only
/// non-identifying event names and coarse parameters; never emails, names,
/// exact trade sizes/lots, account ids or API keys (see `AGENTS.md`).
class TelemetryService {
  TelemetryService._();

  static final TelemetryService instance = TelemetryService._();

  AnalyticsLogger? _analytics;
  FirebaseCrashlytics? _crashlytics;

  /// Wires the real Firebase singletons. Best-effort: leaves the service a
  /// no-op if [FirebaseAnalytics.instance] / [FirebaseCrashlytics.instance]
  /// throw because no default app was initialized.
  void attach() {
    try {
      _analytics = _FirebaseAnalyticsLogger(FirebaseAnalytics.instance);
      _crashlytics = FirebaseCrashlytics.instance;
    } catch (_) {
      _analytics = null;
      _crashlytics = null;
    }
  }

  /// Logs one analytics event. [parameters] are coarse, non-PII values only.
  /// No-op when telemetry is unavailable (mock mode / web / tests).
  void logEvent(String name, [Map<String, Object>? parameters]) {
    final AnalyticsLogger? logger = _analytics;
    if (logger == null) return;
    unawaited(_emit(logger, name, parameters));
  }

  Future<void> _emit(
    AnalyticsLogger logger,
    String name,
    Map<String, Object>? parameters,
  ) async {
    try {
      await logger.logEvent(name, parameters);
    } catch (_) {
      // Best-effort: a logging failure must never surface to the trader.
    }
  }

  /// Segments crash reports and analytics by entitlement tier. [tier] is
  /// `'free'` or `'pro'` — never an account id, email or name.
  void setAppTier(String tier) {
    try {
      _crashlytics?.setCustomKey('app_tier', tier);
    } catch (_) {
      // Crashlytics unavailable — nothing to segment.
    }
  }

  /// Records a non-fatal Crashlytics report for a self-diagnosing failure that
  /// the UI already handled — e.g. a Google sign-in status code. [key] is
  /// attached as a custom key so the report is filterable by that code.
  ///
  /// Best-effort and never throws: a build with no Firebase config degrades to
  /// a no-op, exactly like the rest of this seam. The [key]/[value] pair must be
  /// a non-PII status token (a code), never an email, name or account id.
  void recordNonFatal(String reason, {String? key, Object? value}) {
    final FirebaseCrashlytics? crashlytics = _crashlytics;
    if (crashlytics == null) return;
    unawaited(_recordNonFatal(crashlytics, reason, key, value));
  }

  Future<void> _recordNonFatal(
    FirebaseCrashlytics crashlytics,
    String reason,
    String? key,
    Object? value,
  ) async {
    try {
      if (key != null && value != null) {
        await crashlytics.setCustomKey(key, value);
      }
      await crashlytics.recordError(
        Exception(reason),
        null,
        reason: reason,
        fatal: false,
      );
    } catch (_) {
      // Best-effort: a reporting failure must never surface to the trader.
    }
  }

  /// Test seam: injects a fake [AnalyticsLogger] without a Firebase platform.
  @visibleForTesting
  void debugAttachLogger(AnalyticsLogger logger) => _analytics = logger;

  /// Test seam: returns the service to its no-op default.
  @visibleForTesting
  void debugDetach() {
    _analytics = null;
    _crashlytics = null;
  }
}
