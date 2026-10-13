import 'package:flutter/material.dart';

import '../constants/app_config.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Shown instead of the app when a **release** build starts with no usable
/// Supabase configuration.
///
/// The failure this replaces was silent and expensive: `AppConfig.useMock` used
/// to be `supabaseUrl.isEmpty`, so a release APK built without the required
/// `--dart-define`s booted straight into demo mode — seeded accounts, an
/// auto-signed-in demo user, and a Sign out button that did nothing. A trader who
/// installed that build would reasonably believe their real data was missing.
///
/// Failing loudly is the honest behaviour: the keys are baked in at build time,
/// so there is nothing the person holding the phone can do to fix it. The copy
/// therefore names the fix (rebuild with the required keys) rather than offering
/// a retry that cannot succeed, and it lists exactly which defines are missing.
///
/// Debug and profile builds never reach this screen — they fall back to the
/// seeded mocks, which is what makes `flutter run` work with no keys at all.
class FatalConfigScreen extends StatelessWidget {
  const FatalConfigScreen({super.key});

  /// The exact define names that must be supplied, in a stable order so the
  /// copy is assertable in tests.
  static const List<String> requiredDefines = <String>[
    'SUPABASE_URL',
    'SUPABASE_ANON_KEY',
  ];

  @override
  Widget build(BuildContext context) {
    // Prefer the per-define verdict, but fall back to the canonical list so the
    // screen can never render an empty body.
    final List<String> missing = AppConfig.missingConfigKeys.isEmpty
        ? requiredDefines
        : AppConfig.missingConfigKeys;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Icon(
                    Icons.error_outline,
                    size: 56,
                    color: AppColors.danger,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'App configuration missing',
                    style: AppTextStyles.h1,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This build was compiled without the keys it needs to reach '
                    'the TradeGuard backend, so it cannot start.',
                    style: AppTextStyles.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Rebuild with required keys.',
                    style: AppTextStyles.muted,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('MISSING', style: AppTextStyles.label),
                        const SizedBox(height: 8),
                        for (final String key in missing)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              key,
                              style: AppTextStyles.body.copyWith(
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: const Text(
                      'Add the keys to the release build command, for example:\n\n'
                      'flutter build appbundle --release \\\n'
                      '  --dart-define=SUPABASE_URL=https://<project>.supabase.co \\\n'
                      '  --dart-define=SUPABASE_ANON_KEY=<anon key>\n\n'
                      'See docs/BACKEND_DEPLOY.md for the full command.',
                      style: AppTextStyles.disclaimer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
