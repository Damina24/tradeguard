import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_strings.dart';
import 'core/router/app_router.dart';
import 'core/services/services.dart';
import 'core/services/telemetry_service.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runZonedGuarded<Future<void>>(
    () async {
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
