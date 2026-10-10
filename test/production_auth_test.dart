import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/router/app_router.dart';
import 'package:tradeguard/core/services/auth_provider.dart';
import 'package:tradeguard/core/services/auth_repository.dart';
import 'package:tradeguard/core/services/social_auth.dart';
import 'package:tradeguard/features/auth/presentation/auth_screen.dart';
import 'package:tradeguard/features/settings/presentation/settings_screen.dart';

/// The production auth surface: first launch with no session, and Sign out.
///
/// Settings' Sign out used to be a SnackBar that only *said* "Signed out (demo)"
/// — it never called the repository, so the session survived and the app stayed
/// where it was. These tests drive the real router so the redirect that follows a
/// cleared session is covered too, not just the call itself.
void main() {
  /// The app's real router, so the auth guard's redirect is exercised end to end.
  Widget app(ProviderContainer container) => UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) =>
              MaterialApp.router(routerConfig: ref.watch(routerProvider)),
        ),
      );

  /// A session-backed auth repository: starts signed in as a live user, so
  /// clearing it models a real sign-out rather than the mock auto-sign-in.
  ///
  /// [signedIn] is an explicit flag rather than a nullable `AppUser`, because
  /// `user: null` and omitting the argument are indistinguishable in Dart and
  /// "no session" is exactly the case under test.
  ProviderContainer signedInContainer() {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        authProvider.overrideWith(
          (Ref ref) => AuthNotifier(
            _SignedInRepository(signedIn: true),
            autoSignIn: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('first launch with no session lands on the auth screen', (
    WidgetTester tester,
  ) async {
    // No autoSignIn, no stored session: the router must redirect to /auth rather
    // than admitting an anonymous trader to the Guard screen.
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        authProvider.overrideWith(
          (Ref ref) => AuthNotifier(_SignedInRepository(), autoSignIn: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(app(container));
    await tester.pumpAndSettle();

    expect(container.read(authProvider), isNull);
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    // The five-tab shell is not mounted for an unauthenticated session.
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('Sign out clears the session and routes to the auth screen', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = signedInContainer();

    await tester.pumpWidget(app(container));
    await tester.pumpAndSettle();

    // Starts signed in, so the shell is up.
    expect(container.read(authProvider), isNotNull);
    expect(find.text('Settings'), findsOneWidget);

    // The bottom-nav Settings tab is the documented route to Sign out.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    // The tile is below the fold, so scroll it into view first.
    await tester.scrollUntilVisible(
      find.text('Sign out'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    // The session is genuinely gone — not just reported as gone.
    expect(container.read(authProvider), isNull);
    // And the app moved to /auth.
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    // No leftover SnackBar pretending the session ended.
    expect(find.text('Signed out (demo).'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// Minimal live-shaped auth repository. `currentUser` reports a session only
/// until [signOut] runs, so it models a first launch with no session and a real
/// sign-out the same way the Supabase repository does.
class _SignedInRepository implements AuthRepository {
  _SignedInRepository({this.signedIn = false});

  /// Whether a session exists on boot. False models a first launch.
  bool signedIn;

  static const AppUser _session =
      AppUser(id: 'live-user', email: 'trader@example.com');

  AppUser? get _user => signedIn ? _session : null;

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
  }

  @override
  Future<AuthOutcome> signIn(String email, String password) async =>
      const AuthOutcome.success(AppUser(id: 'live-user'));

  @override
  Future<AuthOutcome> signUp(String email, String password) async =>
      const AuthOutcome.success(AppUser(id: 'live-user'));

  @override
  Future<void> signOut() async {
    signedIn = false;
  }

  @override
  Future<AuthOutcome> sendPasswordReset(String email) async =>
      const AuthOutcome.done();

  @override
  Future<AuthOutcome> signInWithProvider(SocialProvider provider) async =>
      const AuthOutcome.done();
}
