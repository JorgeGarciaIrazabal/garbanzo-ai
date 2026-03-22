import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' show AutomatedTestWidgetsFlutterBinding;
import 'package:webview_flutter/webview_flutter.dart';

/// A widget that renders Mermaid diagrams using a WebView with mermaid.js.
///
/// This widget loads mermaid.js from a CDN and renders the diagram
/// as SVG. It supports all standard Mermaid diagram types including
/// flowchart, sequence, class, state, etc.
///
/// In test environments, this widget displays a placeholder code block
/// instead of rendering the diagram.
class MermaidDiagram extends StatefulWidget {
  const MermaidDiagram({
    super.key,
    required this.mermaidCode,
    required this.colorScheme,
    this.onHeightChanged,
    this.isTestMode = false,
  });

  final String mermaidCode;
  final ColorScheme colorScheme;
  final void Function(double height)? onHeightChanged;

  /// When true, shows a placeholder code block instead of the WebView.
  /// This is useful for widget tests where WebView is not supported.
  final bool isTestMode;

  /// Returns true if running in a test environment.
  static bool get isRunningInTest {
    // Check if we're in a widget test environment
    return WidgetsBinding.instance is AutomatedTestWidgetsFlutterBinding;
  }

  @override
  State<MermaidDiagram> createState() => _MermaidDiagramState();
}

class _MermaidDiagramState extends State<MermaidDiagram> {
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  double _diagramHeight = 300.0; // Default height
  bool _copied = false;

  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    if (!widget.isTestMode && !kIsWeb) {
      // Only initialize WebView on non-web platforms when not in test mode
      _initializeWebView();
    }
  }

  @override
  void didUpdateWidget(MermaidDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mermaidCode != widget.mermaidCode && _controller != null) {
      _renderDiagram();
    }
  }

  void _initializeWebView() {
    final isDark = widget.colorScheme.brightness == Brightness.dark;
    final backgroundColor = isDark ? '#1e1e1e' : '#ffffff';
    final textColor = isDark ? '#e0e0e0' : '#37474f';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'MermaidChannel',
        onMessageReceived: _handleJavaScriptMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            _renderDiagram();
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
                _errorMessage = 'Failed to load diagram: ${error.description}';
              });
            }
          },
        ),
      )
      ..loadHtmlString(_buildHtml(backgroundColor, textColor));
  }

  void _handleJavaScriptMessage(JavaScriptMessage message) {
    final data = jsonDecode(message.message) as Map<String, dynamic>;
    final type = data['type'] as String;

    switch (type) {
      case 'ready':
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        break;
      case 'height':
        final height = (data['height'] as num?)?.toDouble() ?? 300.0;
        if (mounted) {
          setState(() {
            _diagramHeight = height.clamp(100.0, 2000.0);
          });
          widget.onHeightChanged?.call(_diagramHeight);
        }
        break;
      case 'error':
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
            _errorMessage = data['message'] as String?;
          });
        }
        break;
    }
  }

  Future<void> _renderDiagram() async {
    if (_controller == null || _isLoading) {
      // Still initializing, will render after page finishes loading
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    final isDark = widget.colorScheme.brightness == Brightness.dark;
    final theme = isDark ? 'dark' : 'default';

    // Escape the mermaid code for JavaScript
    final escapedCode = widget.mermaidCode
        .replaceAll('\\', '\\\\')
        .replaceAll('`', '\\`')
        .replaceAll('\$', '\\\$');

    await _controller!.runJavaScript('''
      (function() {
        try {
          mermaid.initialize({
            startOnLoad: false,
            theme: '$theme',
            securityLevel: 'loose',
            flowchart: { useMaxWidth: true, htmlLabels: true },
            sequence: { useMaxWidth: true },
            gantt: { useMaxWidth: true }
          });

          const code = `$escapedCode`;
          const id = 'mermaid-' + Date.now();

          mermaid.render(id, code).then(function(result) {
            document.getElementById('diagram').innerHTML = result.svg;

            // Calculate and report height
            const svg = document.querySelector('svg');
            if (svg) {
              const height = svg.getBBox().height + 20;
              MermaidChannel.postMessage(JSON.stringify({
                type: 'height',
                height: Math.max(height, 100)
              }));
            }

            MermaidChannel.postMessage(JSON.stringify({ type: 'ready' }));
          }).catch(function(error) {
            MermaidChannel.postMessage(JSON.stringify({
              type: 'error',
              message: error.message || 'Failed to render diagram'
            }));
          });
        } catch (e) {
          MermaidChannel.postMessage(JSON.stringify({
            type: 'error',
            message: e.message || 'Unexpected error'
          }));
        }
      })();
    ''');
  }

  String _buildHtml(String backgroundColor, String textColor) {
    final escapedCode = widget.mermaidCode
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    body {
      background-color: transparent;
      color: $textColor;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      justify-content: center;
      align-items: flex-start;
      min-height: 100px;
      overflow-x: auto;
    }
    #diagram {
      display: flex;
      justify-content: center;
      align-items: center;
      padding: 10px;
      width: 100%;
    }
    #diagram svg {
      max-width: 100%;
      height: auto;
    }
    .error {
      color: #ef4444;
      padding: 16px;
      text-align: center;
      font-family: monospace;
    }
    .loading {
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .loading::after {
      content: '';
      width: 20px;
      height: 20px;
      border: 2px solid #888;
      border-top-color: transparent;
      border-radius: 50%;
      animation: spin 1s linear infinite;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
  </style>
</head>
<body>
  <div id="diagram" class="loading"></div>
  <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
  <script>
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'loose',
      flowchart: { useMaxWidth: true, htmlLabels: true },
      sequence: { useMaxWidth: true },
      gantt: { useMaxWidth: true }
    });

    // Store the mermaid code for rendering
    window.mermaidCode = "$escapedCode";
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    // In test mode, on web, or in a test environment, show a placeholder code block
    if (widget.isTestMode || kIsWeb || MermaidDiagram.isRunningInTest) {
      return _buildTestModeWidget();
    }

    if (_hasError) {
      return _buildErrorWidget();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: widget.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(),
          // Diagram content
          SizedBox(
            height: _diagramHeight,
            child: Stack(
              children: [
                if (_controller != null)
                  WebViewWidget(controller: _controller!),
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      color: widget.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build a placeholder widget for test mode or web platform.
  Widget _buildTestModeWidget() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: widget.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(),
          // Placeholder content
          Container(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_tree_outlined,
                      size: 16,
                      color: widget.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Mermaid Diagram',
                      style: widget.colorScheme.brightness == Brightness.dark
                          ? TextStyle(
                              color: widget.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            )
                          : TextStyle(
                              color: widget.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    widget.mermaidCode,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: widget.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: widget.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
        border: Border(
          bottom: BorderSide(
            color: widget.colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 14,
                color: widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Text(
                'mermaid',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          InkWell(
            onTap: _copyCode,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _copied ? Icons.check : Icons.copy_outlined,
                    size: 14,
                    color: _copied
                        ? widget.colorScheme.primary
                        : widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _copied ? 'Copied!' : 'Copy',
                    style: TextStyle(
                      fontSize: 12,
                      color: _copied
                          ? widget.colorScheme.primary
                          : widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: widget.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.colorScheme.error.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Error header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 14,
                  color: widget.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Text(
                  'Mermaid Diagram Error',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.colorScheme.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Error message
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              _errorMessage ?? 'Failed to render diagram',
              style: TextStyle(
                fontSize: 12,
                color: widget.colorScheme.onErrorContainer,
              ),
            ),
          ),
          // Raw code fallback
          Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.mermaidCode,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: widget.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.mermaidCode));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _copied = false);
    }
  }
}