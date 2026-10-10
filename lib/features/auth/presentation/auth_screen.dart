import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/services/auth_provider.dart';
import '../../../core/services/auth_repository.dart';
import '../../../core/services/services.dart';
import '../../../core/services/social_auth.dart';
import '../../../core/services/telemetry_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/disclaimer_note.dart';
import '../widgets/social_sign_in_buttons.dart';

/// Email + password sign-in, sign-up and password reset on one route.
///
/// Navigation is intentionally *not* done here: `routerProvider`'s redirect swaps `/auth` for
/// `/guard` as soon as the auth stream reports a user, so "am I signed in" has a single source of
/// truth.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  static final RegExp _emailPattern =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _signUp = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final AuthNotifier auth = ref.read(authProvider.notifier);
    final AuthOutcome outcome = _signUp
        ? await auth.signUp(_email.text, _password.text)
        : await auth.signIn(_email.text, _password.text);

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (outcome.needsEmailConfirmation) {
        _error = null;
        _toast('Check your inbox to confirm your email.');
      } else {
        _error = outcome.error;
      }
    });
  }

  Future<void> _resetPassword() async {
    final String email = _email.text.trim();
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _error = 'Enter your email address first.');
      return;
    }
    setState(() => _busy = true);
    final AuthOutcome outcome =
        await ref.read(authProvider.notifier).sendPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = outcome.error;
    });
    if (outcome.isSuccess) {
      _toast('If that email exists, a reset link is on its way.');
    }
  }

  Future<void> _socialSignIn(SocialProvider provider) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final AuthOutcome outcome =
        await ref.read(authProvider.notifier).signInWithProvider(provider);

    if (!mounted) return;
    setState(() {
      _busy = false;
      // A dismissed Apple/Google sheet comes back as a success with no user and no error, so there
      // is nothing to report in that case.
      if (outcome.needsEmailConfirmation) {
        _error = null;
        _toast('Check your inbox to confirm your email.');
      } else if (outcome.error != null &&
          provider == SocialProvider.google &&
          outcome.code != null) {
        // Self-diagnosing Google failure: the trader-safe message stays on
        // screen, while the raw code goes to Crashlytics in release (as the
        // `google_signin_code` custom key) and onto the snackbar in
        // debug/profile so a developer can read it off the device.
        if (kReleaseMode) {
          TelemetryService.instance.recordNonFatal(
            'google-signin-failed',
            key: 'google_signin_code',
            value: outcome.code!,
          );
          _error = outcome.error;
        } else {
          _error = '${outcome.error} (code ${outcome.code})';
        }
      } else {
        _error = outcome.error;
      }
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      _toast('Could not open the link.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool demoMode = Services.instance.isMock;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Icon(
                      Icons.shield_outlined,
                      size: 44,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      AppStrings.storeTitle,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.h1,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      AppStrings.subtitle,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.muted,
                    ),
                    if (demoMode) ...<Widget>[
                      const SizedBox(height: 16),
                      const _DemoBanner(),
                    ],
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      style: AppTextStyles.body,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (String? v) =>
                          (v == null || !_emailPattern.hasMatch(v.trim()))
                              ? 'Enter a valid email address.'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _busy ? null : _submit(),
                      style: AppTextStyles.body,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppColors.textMuted,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (String? v) => (v == null || v.isEmpty)
                          ? 'Enter your password.'
                          : _signUp && v.length < 6
                              ? 'Use at least 6 characters.'
                              : null,
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.danger),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_signUp ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _signUp = !_signUp;
                                _error = null;
                              }),
                      child: Text(
                        _signUp
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account',
                        style: AppTextStyles.muted,
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _resetPassword,
                      child: const Text(
                        'Forgot password?',
                        style: AppTextStyles.muted,
                      ),
                    ),
                    SocialSignInButtons(
                      busy: _busy,
                      onSignIn: _socialSignIn,
                    ),
                    const SizedBox(height: 16),
                    const DisclaimerNote(),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      children: <Widget>[
                        _LegalLink(
                          label: 'Privacy policy',
                          url: AppConfig.privacyUrl,
                          onTap: _open,
                        ),
                        _LegalLink(
                          label: 'Terms of service',
                          url: AppConfig.termsUrl,
                          onTap: _open,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.science_outlined, size: 18, color: AppColors.accent),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Demo mode — signed in as a demo trader with sample accounts.',
              style: AppTextStyles.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.label,
    required this.url,
    required this.onTap,
  });

  final String label;
  final String url;
  final Future<void> Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(url),
      child: Text(
        label,
        style:
            AppTextStyles.muted.copyWith(decoration: TextDecoration.underline),
      ),
    );
  }
}
