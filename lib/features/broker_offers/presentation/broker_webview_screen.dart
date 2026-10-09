import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Full-screen affiliate WebView for a partner broker signup / cashback page.
///
/// The page is the broker's, not ours, so navigation is left unrestricted:
/// in-page links load inside the WebView, and the AppBar "open in browser"
/// action hands the current URL to the device's default browser — the escape
/// hatch a broker needs when it sends the user out for KYC or banking.
class BrokerWebViewScreen extends StatefulWidget {
  const BrokerWebViewScreen({required this.url, required this.title, super.key});

  /// The initial affiliate URL to load.
  final String url;

  /// The title shown in the AppBar (the broker name).
  final String title;

  @override
  State<BrokerWebViewScreen> createState() => _BrokerWebViewScreenState();
}

class _BrokerWebViewScreenState extends State<BrokerWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _hasError = false;
  double _progress = 0;
  late String _currentUrl;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) =>
              setState(() => _progress = progress / 100),
          onPageStarted: (String url) => setState(() {
            _loading = true;
            _hasError = false;
            _currentUrl = url;
          }),
          onPageFinished: (String url) => setState(() {
            _loading = false;
            _currentUrl = url;
          }),
          onWebResourceError: (_) => setState(() {
            _loading = false;
            _hasError = true;
          }),
        ),
      );
    // `loadRequest` throws synchronously on a scheme-less URI, so only load a
    // real URL. An empty `url` (e.g. a malformed deep link) renders the frame
    // rather than crashing the screen.
    if (widget.url.isNotEmpty) {
      _controller.loadRequest(Uri.parse(widget.url));
    }
  }

  Future<void> _openExternally() async {
    final Uri uri = Uri.parse(_currentUrl);
    final bool opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the browser.')),
      );
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _hasError = false;
      _progress = 0;
    });
    _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_new),
            onPressed: _openExternally,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_loading)
            LinearProgressIndicator(
              value: _progress,
              minHeight: 3,
              backgroundColor: AppColors.surfaceAlt,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          Expanded(
            child: _hasError
                ? _ErrorView(onRetry: _retry)
                : WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.cloud_off, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 16),
            const Text('Failed to load broker', style: AppTextStyles.title),
            const SizedBox(height: 8),
            const Text(
              'Check your connection and try again, or open the page in your '
              'browser.',
              textAlign: TextAlign.center,
              style: AppTextStyles.muted,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
