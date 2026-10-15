import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_config.dart';
import 'core/constants/app_strings.dart';
import 'core/router/app_router.dart';
import 'core/services/auth_error_guard.dart';
import 'core/services/services.dart';
import 'core/services/telemetry_service.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/fatal_config_screen.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      // 1. THIS MUST BE THE VERY FIRST LINE INSIDE THE ZONE
      WidgetsFlutterBinding.ensureInitialized();

      // A release build with no usable Supabase config stops here, before any
      // backend, telemetry or router work. It must NOT fall back to demo data:
      // a release APK is what a trader installs, and showing them seeded
      // accounts looks exactly like their real account vanished. Nothing on the
      // device can fix a missing compile-time key, so say so and stop.
      if (AppConfig.configMissing) {
        runApp(
          MaterialApp(
            title: AppStrings.storeTitle,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            home: const FatalConfigScreen(),
          ),
        );
        return;
      }

      // Firebase first, inside the guarded zone: Crashlytics' zone handler and
      // Analytics both read the default app, so it must exist before either is
      // touched. `firebase_core` owns native init, so AppDelegate.swift is left
      // untouched. A build with no google-services.json / GoogleService-Info.plist
      // (mock mode, web, tests) throws here — that must degrade telemetry, not
      // crash the app, exactly as FcmPushService.init() already does.
      try {
        await Firebase.initializeApp();

        // Framework errors become Crashlytics reports.
        FlutterError.onError =
            FirebaseCrashlytics.instance.recordFlutterFatalError;

        // Ship crashes only from release builds; debug/profile stay silent.
        await FirebaseCrashlytics.instance
            .setCrashlyticsCollectionEnabled(kReleaseMode);

        // Hand the live singletons to the PII-safe telemetry seam.
        TelemetryService.instance.attach();
      } catch (_) {
        // No Firebase config (mock mode / web): telemetry stays a no-op.
      }

      // No-op in mock mode; boots the Supabase client when SUPABASE_URL is set.
      await Services.instance.init();

      runApp(const ProviderScope(child: TradeGuardApp()));
    },
    (Object error, StackTrace stack) {
      // GoTrue's background auto-refresh can also escape through paths that
      // never touch our `onAuthStateChange` handler (e.g. `recoverSession()`
      // rethrows after notifying, and the retryable `AuthRetryableFetchException`
      // wrapping `SocketException: Failed host lookup` fires exactly when
      // Android restricts network access while backgrounded). Those are
      // transient: the SDK retries on its own when the app returns to the
      // foreground, so swallow them here instead of filing a fatal crash —
      // and never sign the user out over them.
      if (isBackgroundNetworkError(error)) {
        handleBackgroundAuthError(error, stack);
        return;
      }
      // Anything that escapes the zone lands here. Best-effort: if Firebase
      // never came up, recordError would itself throw and mask the original,
      // so guard it and keep the zone's default debug output.
      try {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      } catch (_) {
        debugPrint('Uncaught error (Crashlytics unavailable): $error');
      }
    },
  );
}

class TradeGuardApp extends ConsumerWidget {
  const TradeGuardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: AppStrings.storeTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
