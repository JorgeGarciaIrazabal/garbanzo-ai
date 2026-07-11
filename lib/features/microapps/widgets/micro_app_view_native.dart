// Native implementation of [MicroAppView]. On Android/iOS it embeds a real
// WebView; on desktop (where webview_flutter has no platform support) it shows
// an "open in browser" fallback. Compiled on all non-web platforms.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

Widget microAppPlatformView({required String url, required int reloadCounter}) {
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    return _WebViewHost(url: url, reloadCounter: reloadCounter);
  }
  return _OpenInBrowserCard(url: url);
}

class _WebViewHost extends StatefulWidget {
  final String url;
  final int reloadCounter;
  const _WebViewHost({required this.url, required this.reloadCounter});

  @override
  State<_WebViewHost> createState() => _WebViewHostState();
}

class _WebViewHostState extends State<_WebViewHost> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void didUpdateWidget(_WebViewHost old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _controller.loadRequest(Uri.parse(widget.url));
    } else if (old.reloadCounter != widget.reloadCounter) {
      _controller.reload();
    }
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

class _OpenInBrowserCard extends StatelessWidget {
  final String url;
  const _OpenInBrowserCard({required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.open_in_browser,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Preview not embeddable on this platform',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Open this URL in a browser to view the app. Agent edits still '
              'apply live to the shared workspace.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SelectableText(url, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy URL'),
              onPressed: () => Clipboard.setData(ClipboardData(text: url)),
            ),
          ],
        ),
      ),
    );
  }
}
