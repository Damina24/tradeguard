import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

/// Professional boot / loading screen shown immediately after the native
/// splash hides and before the router settles on `/guard` (or `/auth`).
///
/// * Logo uses [BoxFit.contain] inside a large bounded box, so it fills the
///   screen beautifully on any size/density without stretching or cropping.
/// * A [CircularProgressIndicator] below the logo signals active launching.
/// * Background is [AppColors.background] (`#0A0E17`), identical to the
///   `flutter_native_splash` `color` in `pubspec.yaml` and to
///   `AppTheme.dark.scaffoldBackgroundColor`, so the native -> Flutter
///   handoff has no flash.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// How long the splash stays visible before handing off to the router.
  /// Long enough for the spinner to read as "loading", short enough to
  /// feel instant. Tests using `pumpAndSettle` advance past it.
  static const Duration dwell = Duration(milliseconds: 1500);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate after the dwell. Always target `/guard` and let the
    // router's auth redirect bounce unauthenticated users to `/auth` —
    // the splash itself never needs to read auth state.
    // The try/catch keeps standalone harnesses (widget tests mounting
    // SplashScreen without a GoRouter) from throwing when the timer fires.
    Future<void>.delayed(SplashScreen.dwell, () {
      if (!mounted) return;
      try {
        context.go('/guard');
      } catch (_) {
        // No GoRouter in scope (e.g. widget test): stay on the splash.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 65% of the shortest side: large on phones and tablets, never
    // overflowing, aspect preserved by BoxFit.contain.
    final double logoSize = MediaQuery.sizeOf(context).shortestSide * 0.65;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: logoSize,
                height: logoSize,
                child: Image.asset(
                  'assets/images/splash_logo.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  semanticLabel: 'TradeGuard logo',
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.primary,
                  semanticsLabel: 'Loading',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
