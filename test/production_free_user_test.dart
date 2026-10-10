import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/account.dart';
import 'package:tradeguard/core/models/trade.dart';
import 'package:tradeguard/core/services/account_repository.dart';
import 'package:tradeguard/core/services/auth_provider.dart';
import 'package:tradeguard/core/services/auth_repository.dart';
import 'package:tradeguard/core/services/social_auth.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/core/services/trade_repository.dart';
import 'package:tradeguard/core/theme/app_theme.dart';
import 'package:tradeguard/features/journal/data/trade_screenshot_service.dart';
import 'package:tradeguard/features/journal/presentation/journal_screen.dart';

/// The production FREE-user path the field report implied: a real session, a real
/// (empty) backend, and therefore an empty journal.
///
/// Before the mode-selection fix this state was unreachable in a release build —
/// an unconfigured APK silently became a demo build with seeded accounts and an
/// auto-signed-in demo user, so a trader could never see their own empty journal.
/// These tests drive live-shaped repositories and assert the seeded fixtures do
/// NOT leak into them.
void main() {
  /// Builds a container over empty, live-shaped repositories. [signedIn] models
  /// whether a session exists on boot.
  ProviderContainer containerWith({required bool signedIn}) {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        authProvider.overrideWith(
          (Ref ref) => AuthNotifier(_Session(signedIn: signedIn), autoSignIn: false),
        ),
        accountsProvider.overrideWith(
          (Ref ref) => AccountsNotifier(_Accounts()),
        ),
        tradesProvider.overrideWith(
          (Ref ref) => TradesNotifier(_Trades(), screenshots: _NoScreenshots()),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a live-shaped account repository returns no seeded demo accounts', () async {
    // Regression guard for the seeded-data leak: the live repository must not
    // hand back the FTMO/FUNDED fixtures that mock mode uses.
    expect(await _Accounts().fetchAccounts(), isEmpty);
  });

  test('a live-shaped trade repository returns no seeded demo trades', () async {
    expect(await _Trades().fetchTrades(), isEmpty);
  });

  test('auth starts null for a first launch with no session', () {
    expect(containerWith(signedIn: false).read(authProvider), isNull);
  });

  test('a signed-in session is a real user, not the demo user', () {
    final ProviderContainer c = containerWith(signedIn: true);
    expect(c.read(authProvider), isNotNull);
    // Explicitly not the mock auto-sign-in identity.
    expect(c.read(authProvider)?.id, isNot('demo-user'));
    expect(c.read(authProvider)?.email, isNot('demo@tradeguard.app'));
  });

  testWidgets('the journal shows an empty state, not seeded trades', (
    WidgetTester tester,
  ) async {
    final ProviderContainer c = containerWith(signedIn: true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.dark, home: const JournalScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // The screen itself renders — this is a real empty journal, not an error.
    expect(find.text('NET P&L'), findsOneWidget);

    // No seeded account nickname anywhere in the tree.
    expect(find.text('FTMO EVAL 100K'), findsNothing);
    expect(find.text('FUNDED 50K'), findsNothing);

    // The empty state sits below the stats and calendar, and a ListView builds
    // children lazily, so scroll it into view before asserting.
    await tester.scrollUntilVisible(
      find.text('No broker connected'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // The empty state says WHY, which for a brokerless account is the actionable
    // part: connect a broker.
    expect(find.text('No broker connected'), findsOneWidget);
    expect(find.textContaining('Connect a broker account'), findsOneWidget);

    expect(c.read(tradesProvider), isEmpty);
    expect(c.read(accountsProvider), isEmpty);
    expect(tester.takeException(), isNull);
  });
}

/// Repositories shaped like the Supabase ones: they answer with exactly what the
/// backend holds, which for a brand-new trader is nothing at all. Named without
/// a "Mock" prefix on purpose — nothing in here is seeded.
class _Accounts implements AccountRepository {
  @override
  // A fresh list, not `const <TradingAccount>[]` — see the note on `_Trades`.
  Future<List<TradingAccount>> fetchAccounts() async =>
      List<TradingAccount>.unmodifiable(<TradingAccount>[]);

  @override
  Future<AccountSnapshot> fetchSnapshot(String accountId) async =>
      throw StateError('Unknown account: $accountId');

  @override
  Future<TradingAccount> createAccount(TradingAccount account) async => account;

  @override
  Future<void> deleteAccount(String accountId) async {}

  @override
  Future<void> setEquityGuardEnabled(String accountId, bool enabled) async {}

  @override
  Future<void> setCopyEnabled(String accountId, bool enabled) async {}
}

class _Trades implements TradeRepository {
  @override
  // A FRESH list, not `const <Trade>[]`: StateNotifier compares identity, and the
  // canonical const empty list is the same instance as the notifier's initial
  // state — returning it would publish no change and the Journal would spin on
  // its loading state forever. Both real repositories build a new list too.
  Future<List<Trade>> fetchTrades({String? accountId, int limit = 200}) async =>
      List<Trade>.unmodifiable(<Trade>[]);

  @override
  Future<void> updateGrade(String tradeId, String grade) async {}

  @override
  Future<void> updateNotes(String tradeId, String notes) async {}

  @override
  Future<void> updateScreenshot(String tradeId, String screenshotPath) async {}
}

class _NoScreenshots implements TradeScreenshotService {
  @override
  Future<String> upload({
    required String tradeId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async =>
      '$tradeId/$fileName';

  @override
  Future<Uint8List?> download(String? path) async => null;

  @override
  Future<PickedScreenshot?> pickFromGallery() async => null;
}

/// Session-backed auth for the production tests.
class _Session implements AuthRepository {
  _Session({required this.signedIn});

  /// Whether a session exists on boot. False models a first launch.
  final bool signedIn;

  static const AppUser _user =
      AppUser(id: 'live-user', email: 'trader@example.com');

  @override
  AppUser? get currentUser => signedIn ? _user : null;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield currentUser;
  }

  @override
  Future<AuthOutcome> signIn(String email, String password) async =>
      const AuthOutcome.success(AppUser(id: 'live-user', email: 'trader@example.com'));

  @override
  Future<AuthOutcome> signUp(String email, String password) async =>
      const AuthOutcome.success(AppUser(id: 'live-user', email: 'trader@example.com'));

  @override
  Future<void> signOut() async {}

  @override
  Future<AuthOutcome> sendPasswordReset(String email) async =>
      const AuthOutcome.done();

  @override
  Future<AuthOutcome> signInWithProvider(SocialProvider provider) async =>
      const AuthOutcome.success(AppUser(id: 'live-user', email: 'trader@example.com'));
}
