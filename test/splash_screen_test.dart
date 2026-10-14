import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/theme/app_colors.dart';
import 'package:tradeguard/core/widgets/splash_screen.dart';

void main() {
  group('SplashScreen', () {
    testWidgets('shows large logo with contain fit and loading spinner',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
      await tester.pump();

      // Logo is present and preserves aspect ratio (no stretch/distortion).
      expect(find.bySemanticsLabel('TradeGuard logo'), findsOneWidget);
      final Image image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.contain);

      // Logo is large: sized to 65% of the shortest side.
      final double shortestSide =
          tester.view.physicalSize.shortestSide / tester.view.devicePixelRatio;
      final SizedBox box = tester.widget<SizedBox>(
        find.ancestor(
          of: find.byType(Image),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(box.width, moreOrLessEquals(shortestSide * 0.65));

      // Loading indicator signals the app is actively launching.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Background matches the app primary theme color.
      final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppColors.background);

      // Let the timed handoff fire (no GoRouter in scope, so it stays put)
      // and clear the pending timer so teardown is clean.
      await tester.pump(SplashScreen.dwell);
    });
  });
}
