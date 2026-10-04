import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/services/social_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// "Continue with Apple / Google", shown under the email form.
///
/// Apple owns the design of its own button, so `sign_in_with_apple`'s guideline-compliant widget is
/// used verbatim rather than a home-made one; Google gets a matching outlined button.
class SocialSignInButtons extends StatelessWidget {
  const SocialSignInButtons({required this.onSignIn, this.busy = false, super.key});

  final Future<void> Function(SocialProvider provider) onSignIn;

  /// Disables both buttons while any auth call is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 20),
        const _OrDivider(),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: SignInWithAppleButton(
            onPressed: busy ? null : () => onSignIn(SocialProvider.apple),
            text: 'Continue with Apple',
            height: 50,
            style: SignInWithAppleButtonStyle.whiteOutlined,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: busy ? null : () => onSignIn(SocialProvider.google),
          icon: const _GoogleGlyph(),
          label: const Text('Continue with Google'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.divider),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        Expanded(child: Divider(color: AppColors.divider)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: AppTextStyles.muted),
        ),
        Expanded(child: Divider(color: AppColors.divider)),
      ],
    );
  }
}

/// The four-colour Google "G". Google's branding guidelines forbid their font/logo files being
/// reused, so it is drawn rather than shipped as an asset.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GoogleGlyphPainter()),
    );
  }
}

class _GoogleGlyphPainter extends CustomPainter {
  const _GoogleGlyphPainter();

  static const Color _blue = Color(0xFF4285F4);
  static const Color _green = Color(0xFF34A853);
  static const Color _yellow = Color(0xFFFBBC05);
  static const Color _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Rect rect = Rect.fromLTWH(0, 0, w, h);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.22
      ..strokeCap = StrokeCap.butt;

    canvas
      // Blue: the right-hand sweep, from the top-right around to the centre.
      ..drawArc(
        rect.deflate(w * 0.11),
        -1.5708,
        3.1416,
        false,
        paint..color = _blue,
      )
      // Green: the bottom-right arc.
      ..drawArc(
        rect.deflate(w * 0.11),
        0,
        1.5708,
        false,
        paint..color = _green,
      )
      // Yellow: the bottom-left arc.
      ..drawArc(
        rect.deflate(w * 0.11),
        1.5708,
        1.5708,
        false,
        paint..color = _yellow,
      )
      // Red: the left sweep.
      ..drawArc(
        rect.deflate(w * 0.11),
        3.1416,
        1.0472,
        false,
        paint..color = _red,
      )
      // The horizontal bar across the middle.
      ..drawLine(
        Offset(w * 0.5, h * 0.5),
        Offset(w * 0.92, h * 0.5),
        paint
          ..color = _blue
          ..strokeWidth = w * 0.22,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}