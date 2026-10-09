import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/theme/app_theme.dart';
import 'package:tradeguard/features/broker_offers/presentation/broker_webview_screen.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Registers a no-op [WebViewPlatform] so the screen can build a real
/// [WebViewController] under test. The controller asserts that a platform is
/// set before construction, and every platform method used by the screen is
/// stubbed to a completed future — nothing here touches a real engine.
class _FakeWebViewPlatform extends WebViewPlatform {
  /// The most recent [PlatformNavigationDelegate] handed to a controller, so a
  /// test can reach the callbacks the screen actually registered.
  _FakePlatformNavigationDelegate? lastNavigationDelegate;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) =>
      _FakePlatformWebViewController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    lastNavigationDelegate = _FakePlatformNavigationDelegate(params);
    return lastNavigationDelegate!;
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) =>
      _FakePlatformWebViewWidget(params);
}

class _FakePlatformWebViewController extends PlatformWebViewController {
  _FakePlatformWebViewController(super.params) : super.implementation();

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> reload() async {}
}

/// Captures the navigation callbacks the screen registers, so a test can drive
/// them (e.g. fire an error) without a native web view.
class _FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  _FakePlatformNavigationDelegate(super.params) : super.implementation();

  WebResourceErrorCallback? onWebResourceError;
  PageEventCallback? onPageFinished;
  ProgressCallback? onProgress;

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback callback,
  ) async {
    onWebResourceError = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    onPageFinished = callback;
  }

  @override
  Future<void> setOnProgress(ProgressCallback callback) async {
    onProgress = callback;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {}

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
}

class _FakePlatformWebViewWidget extends PlatformWebViewWidget {
  _FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  late _FakeWebViewPlatform platform;

  setUpAll(() {
    platform = _FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
  });

  testWidgets('shows the broker title and an external browser action',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const BrokerWebViewScreen(
          url: 'https://example.com/signup?ref=tradeguard',
          title: 'FTMO',
        ),
      ),
    );
    await tester.pump();

    // AppBar title is the broker name passed in.
    expect(find.text('FTMO'), findsOneWidget);

    // The external browser escape hatch (for KYC / banking flows) is present.
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    expect(find.byTooltip('Open in browser'), findsOneWidget);

    // The webview itself is mounted behind the loading bar.
    expect(find.byType(WebViewWidget), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('a web resource error swaps in the retry UI',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const BrokerWebViewScreen(
          url: 'https://example.com/signup?ref=tradeguard',
          title: 'FTMO',
        ),
      ),
    );
    await tester.pump();

    // The screen registered its callbacks on the delegate the fake platform
    // handed it during initState. Fire the resource-error callback directly.
    final _FakePlatformNavigationDelegate? delegate =
        platform.lastNavigationDelegate;
    expect(delegate?.onWebResourceError, isNotNull);
    delegate!.onWebResourceError!(const _TestWebResourceError());
    await tester.pump();

    expect(find.text('Failed to load broker'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}

/// Minimal [WebResourceError] to drive the error path.
class _TestWebResourceError extends WebResourceError {
  const _TestWebResourceError()
      : super(
          errorCode: -2,
          description: 'net::ERR_NAME_NOT_RESOLVED',
          errorType: WebResourceErrorType.hostLookup,
          isForMainFrame: true,
        );
}
