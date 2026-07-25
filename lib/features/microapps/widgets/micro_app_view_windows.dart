// Windows implementation of the micro-app preview. Uses flutter_inappwebview's
// WebView2 backend so the live app renders inline beside the chat on Windows
// desktop, instead of the "open in browser" fallback used on Linux/macOS
// (where a stable inline-webview plugin isn't available).
//
// Guarded by a `dart:io` Platform.isWindows check so the plugin compiles on
// every non-web platform but is only constructed on Windows — the shared
// native view routes there, and falls back to `_OpenInBrowserCard` elsewhere.
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Constructs the in-app webview widget for the micro-app preview.
/// Only call when [Platform.isWindows] is true (see micro_app_view_native.dart).
Widget microAppWindowsInAppWebView({
  required String url,
  required int reloadCounter,
}) {
  return _InAppWebViewHost(url: url, reloadCounter: reloadCounter);
}

class _InAppWebViewHost extends StatefulWidget {
  final String url;
  final int reloadCounter;
  const _InAppWebViewHost({required this.url, required this.reloadCounter});

  @override
  State<_InAppWebViewHost> createState() => _InAppWebViewHostState();
}

class _InAppWebViewHostState extends State<_InAppWebViewHost> {
  InAppWebViewController? _controller;
  // Mirrors the webview_flutter native view's load-state model so the panel
  // surfaces a retry card on failure instead of a silent blank. Null =
  // unknown/loading, true = loaded, false = top-frame HTTP/resource error.
  bool? _loadOk;

  @override
  Widget build(BuildContext context) {
    if (_loadOk == false) {
      return _LoadFailedCard(onRetry: _retry);
    }
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.url)),
          onWebViewCreated: (controller) => _controller = controller,
          onLoadStart: (controller, url) {
            if (mounted) setState(() => _loadOk = null);
          },
          onLoadStop: (controller, url) {
            // A page that arrived (even a dev-server 404 body) is not known-bad
            // until onReceivedHttpError/onReceivedError says otherwise. The
            // optimistic-then-err model matches the webview_flutter path so
            // both platforms behave identically.
            if (mounted && _loadOk == null) setState(() => _loadOk = true);
          },
          onReceivedHttpError: (controller, request, response) {
            // Only the top frame determines "the app didn't load": a sub-asset
            // 404 must not replace the panel with the retry card. The dev
            // server's 404 body ("not found") is the stale-worktree failure the
            // user saw, so surfacing it here turns the silent blank into an
            // actionable Retry.
            final isMainFrame = request.isForMainFrame ?? false;
            final status = response.statusCode ?? 0;
            if (isMainFrame && status >= 400 && mounted) {
              setState(() => _loadOk = false);
            }
          },
          onReceivedError: (controller, request, error) {
            // DNS failure, connection refused, cleartext-blocked, etc.
            final isMainFrame = request.isForMainFrame ?? true;
            if (isMainFrame && mounted) setState(() => _loadOk = false);
          },
        ),
        if (_loadOk == null)
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ],
    );
  }

  @override
  void didUpdateWidget(_InAppWebViewHost old) {
    super.didUpdateWidget(old);
    final controller = _controller;
    if (controller == null) return;
    if (old.url != widget.url) {
      setState(() => _loadOk = null);
      controller.loadUrl(urlRequest: URLRequest(url: WebUri(widget.url)));
    } else if (old.reloadCounter != widget.reloadCounter) {
      setState(() => _loadOk = null);
      controller.reload();
    }
  }

  void _retry() {
    setState(() => _loadOk = null);
    _controller?.reload();
  }
}

class _LoadFailedCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _LoadFailedCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              l10n.titleMicroAppLoadFailed,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.messageMicroAppLoadFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.labelRetry),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
