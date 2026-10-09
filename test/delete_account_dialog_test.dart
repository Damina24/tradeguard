import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/services/auth_provider.dart';
import 'package:tradeguard/core/services/auth_repository.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/core/services/social_auth.dart';
import 'package:tradeguard/core/theme/app_theme.dart';
import 'package:tradeguard/features/settings/data/mock_delete_account_repository.dart';
import 'package:tradeguard/features/settings/domain/delete_account.dart';
import 'package:tradeguard/features/settings/presentation/delete_account_dialog.dart';

/// The destructive account-deletion confirmation dialog (store compliance:
/// Apple 5.1.1(v), Google Play account-deletion).
///
/// These tests assert the two things a store reviewer checks and the two a trader depends on:
///   * the confirm is GATED — the Delete button is disabled until the irreversibility checkbox is
///     checked, so a deletion can never be a single stray tap;
///   * success SIGNS OUT (auth goes null) and confirms; and
///   * failure shows a trader-safe message, keeps the trader signed in, and never leaks raw server
///     text.
///
/// The gateway is a mock ([MockDeleteAccountRepository]) injected via
/// `deleteAccountRepositoryProvider`, exactly as the copy-confirm sheet injects its repository —
/// no backend, no network.
void main() {
  const String ackText = 'I understand this is permanent and cannot be undone.';

  /// Pumps the dialog through a real `showDialog` inside an
  /// [UncontrolledProviderScope], so `Navigator.pop` and the snackbar have a
  /// real route and messenger. Returns the container so a test can read
  /// `authProvider` after the flow.
  Future<ProviderContainer> pumpDialog(
    WidgetTester tester,
    MockDeleteAccountRepository repo,
  ) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        deleteAccountRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith(
          (_) => AuthNotifier(
            MockAuthRepository(MockSocialAuthService()),
            autoSignIn: true,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const DeleteAccountDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  TextButton deleteButton(WidgetTester tester) =>
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Delete'));

  testWidgets('the Delete button is disabled until the checkbox is checked', (
    WidgetTester tester,
  ) async {
    await pumpDialog(tester, MockDeleteAccountRepository());

    // Two-step confirmation: step 2 is the checkbox, and Delete stays disabled before it.
    expect(deleteButton(tester).onPressed, isNull);
    expect(find.text(ackText), findsOneWidget);

    await tester.tap(find.text(ackText));
    await tester.pumpAndSettle();

    expect(deleteButton(tester).onPressed, isNotNull);
  });

  testWidgets('the dialog states the subscription must be cancelled manually', (
    WidgetTester tester,
  ) async {
    await pumpDialog(tester, MockDeleteAccountRepository());
    expect(find.textContaining('does NOT cancel an active subscription'), findsOneWidget);
    expect(find.textContaining('App Store or Google Play'), findsOneWidget);
  });

  testWidgets('a successful deletion signs the trader out and confirms', (
    WidgetTester tester,
  ) async {
    final MockDeleteAccountRepository repo = MockDeleteAccountRepository();
    final ProviderContainer container = await pumpDialog(tester, repo);

    // Starts signed in (autoSignIn: true), so a null afterwards proves the sign-out ran.
    expect(container.read(authProvider), isNotNull);

    await tester.tap(find.text(ackText));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.callCount, 1);
    // Signed out: auth is null, the dialog has closed, and a confirmation is shown.
    expect(container.read(authProvider), isNull);
    expect(find.byType(DeleteAccountDialog), findsNothing);
    expect(
      find.text('Your account and data have been deleted.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed deletion shows a safe message and keeps the trader signed in', (
    WidgetTester tester,
  ) async {
    final MockDeleteAccountRepository repo = MockDeleteAccountRepository(
      failure: const DeleteAccountException(DeleteAccountFailure.server),
    );
    final ProviderContainer container = await pumpDialog(tester, repo);

    await tester.tap(find.text(ackText));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    // The trader-safe copy is shown, the account is NOT deleted, and the trader stays signed in.
    expect(
      find.text('We could not delete your account right now. Please try again.'),
      findsOneWidget,
    );
    expect(container.read(authProvider), isNotNull);
    expect(find.byType(DeleteAccountDialog), findsOneWidget);
  });
}
