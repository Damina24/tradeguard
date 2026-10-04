import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/services/broker_connect_service.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/core/theme/app_theme.dart';
import 'package:tradeguard/features/accounts/presentation/connect_broker_sheet.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(theme: AppTheme.dark, home: Scaffold(body: child)),
    );

/// The inner [TextField] that [ConnectBrokerSheet] builds inside each [TextFormField]. Its
/// `obscureText` / `controller` are readable, which is what the credential tests assert on.
Finder _field(String label) => find.descendant(
      of: find.byType(TextFormField),
      matching: find.byWidgetPredicate(
        (Widget w) => w is TextField && w.decoration?.labelText == label,
      ),
    );

TextField _fieldWidget(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label));

/// Pump [child] with [service] installed so the connect call is deterministic.
Widget _wrapWith(BrokerConnectService service, {Widget? child}) =>
    ProviderScope(
      overrides: <Override>[
        connectAccountProvider.overrideWith(
          (Ref ref) => ConnectAccountNotifier(
            service,
            ref.read(accountsProvider.notifier),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: child ?? const ConnectBrokerSheet()),
      ),
    );

void main() {
  group('ConnectBrokerSheet', () {
    // The sheet is a scrollable form. The default 800x600 test viewport only lays out the first
    // few fields, so [pumpSheet] gives it a tall surface and the whole form becomes assertable.
    Future<void> pumpSheet(
      WidgetTester tester,
      Widget sheet, {
      BrokerConnectService? service,
    }) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        service == null
            ? _wrap(sheet)
            : _wrapWith(service, child: sheet),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the read-only promise, form and credential notice', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester, const ConnectBrokerSheet());

      expect(find.text('Connect broker'), findsOneWidget);
      expect(find.textContaining('Read-only'), findsOneWidget);
      expect(find.text('Account number'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Nickname'), findsOneWidget);
      expect(find.text('Enable equity guard'), findsOneWidget);
      // Compliance: the credential-handling notice must be on this surface.
      expect(find.textContaining('never your credentials'), findsOneWidget);
      // Demo mode is disclosed, not hidden.
      expect(find.textContaining('Demo mode'), findsOneWidget);
    });

    testWidgets('password stays obscured until the eye is tapped', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester, const ConnectBrokerSheet());

      expect(_fieldWidget(tester, 'Password').obscureText, isTrue);

      // The eye button reveals the password.
      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pumpAndSettle();

      expect(_fieldWidget(tester, 'Password').obscureText, isFalse);
    });

    testWidgets('account number field rejects letters', (
      WidgetTester tester,
    ) async {
      await pumpSheet(tester, const ConnectBrokerSheet());

      await tester.enterText(_field('Account number'), 'abc123');
      await tester.pumpAndSettle();

      expect(find.text('123'), findsOneWidget);
      expect(find.text('abc123'), findsNothing);
    });

    testWidgets('blocks submit when required fields are empty', (
      WidgetTester tester,
    ) async {
      await pumpSheet(
        tester,
        const ConnectBrokerSheet(),
        service: MockBrokerConnectService(latency: Duration.zero),
      );

      await tester.tap(find.text('Connect account'));
      await tester.pumpAndSettle();

      // Still on the sheet — nothing was connected.
      expect(find.text('Connect broker'), findsOneWidget);
      expect(find.text('Connect account'), findsOneWidget);
    });

    testWidgets('surfaces a rejection and clears the password field', (
      WidgetTester tester,
    ) async {
      await pumpSheet(
        tester,
        const ConnectBrokerSheet(),
        service: _RejectingService(),
      );

      await tester.enterText(_field('Account number'), '5012345');
      await tester.enterText(_field('Password'), 'sup3rSecret');
      await tester.enterText(_field('Server'), 'FTMO-Demo');
      await tester.enterText(_field('Nickname'), 'My EVAL');

      await tester.tap(find.text('Connect account'));
      await tester.pumpAndSettle();

      expect(find.text('The broker rejected those details.'), findsOneWidget);
      expect(find.textContaining('sup3rSecret'), findsNothing);
      // The secret does not linger in the widget tree after the call.
      expect(_fieldWidget(tester, 'Password').controller?.text, isEmpty);
    });
  });
}

/// Always rejects, standing in for a MetaAPI refusal.
class _RejectingService implements BrokerConnectService {
  @override
  bool get isStubbed => false;

  @override
  Future<String> connectBroker(BrokerConnectionRequest request) async {
    throw const BrokerConnectException('The broker rejected those details.');
  }
}
