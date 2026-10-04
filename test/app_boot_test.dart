import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/features/auth/presentation/auth_screen.dart';
import 'package:tradeguard/main.dart';

void main() {
  group('app boot', () {
    testWidgets('mock mode boots straight to the Guard screen', (
      WidgetTester tester,
    ) async {
      // Exercises the whole chain: Services -> mock repositories -> providers -> auth
      // redirect -> router -> Guard screen.
      await tester.pumpWidget(const ProviderScope(child: TradeGuardApp()));
      await tester.pumpAndSettle();

      expect(find.text('DAILY LOSS USED'), findsOneWidget);
      expect(find.text('DRAWDOWN DISTANCE'), findsOneWidget);
      expect(find.text('FTMO EVAL 100K'), findsOneWidget);
      // The five-tab shell is mounted, so no redirect to /auth happened.
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('switching account keeps the guard rendering', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const ProviderScope(child: TradeGuardApp()));
      await tester.pumpAndSettle();

      // Both seeded accounts are mounted as chips.
      expect(find.text('FTMO EVAL 100K'), findsOneWidget);
      expect(find.text('FUNDED 50K'), findsOneWidget);

      await tester.tap(find.text('FUNDED 50K'));
      await tester.pumpAndSettle();

      // Selection still resolves to a real account, so the guard does not fall back to a spinner.
      expect(find.text('DAILY LOSS USED'), findsOneWidget);
      expect(find.text('DRAWDOWN DISTANCE'), findsOneWidget);
    });
  });

  group('AuthScreen', () {
    Future<void> pumpAuth(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AuthScreen())),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders store title, fields and compliance copy', (
      WidgetTester tester,
    ) async {
      await pumpAuth(tester);

      expect(find.text('TradeGuard - Forex Signals'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Terms of service'), findsOneWidget);
      // Risk disclaimer must be on the auth surface.
      expect(find.textContaining('high-risk'), findsOneWidget);
      // Demo mode is disclosed rather than hidden.
      expect(find.textContaining('Demo mode'), findsOneWidget);
    });

    testWidgets('validates before calling the repository', (
      WidgetTester tester,
    ) async {
      await pumpAuth(tester);

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
    });

    testWidgets('toggles to create-account mode', (WidgetTester tester) async {
      await pumpAuth(tester);

      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();

      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Already have an account? Sign in'), findsOneWidget);
    });
  });
}
