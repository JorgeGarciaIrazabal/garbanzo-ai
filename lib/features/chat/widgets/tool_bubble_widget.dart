import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/chat/models/chat_message.dart';

/// A single entry on the tool-activity rail — either an MCP tool invocation
/// (`role: tool_call`) or the server's response (`role: tool_result`).
///
/// Renders as a flat, quiet row: status glyph, kind badge, monospace tool
/// name, and a dimmed one-line preview of the payload. Tapping the row
/// expands a formatted JSON block with the full input or output.
class ToolBubbleWidget extends StatefulWidget {
  const ToolBubbleWidget({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  final ChatMessage message;

  /// When true and the message is a `tool_call` without a matching result in
  /// this same bubble, shows a spinner indicating the call is running.
  final bool isStreaming;

  @override
  State<ToolBubbleWidget> createState() => _ToolBubbleWidgetState();
}

class _ToolBubbleWidgetState extends State<ToolBubbleWidget> {
  bool _expanded = false;

  ChatMessage get message => widget.message;

  bool get _isCall => message.isToolCall;
  bool get _isResult => message.isToolResult;

  Map<String, dynamic>? get _callData {
    if (!_isCall) return null;
    final meta = message.metadata;
    if (meta == null) return null;
    final list = meta['tool_calls'];
    if (list is List && list.isNotEmpty) {
      final first = list.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) {
        return first.map((k, v) => MapEntry(k.toString(), v));
      }
    }
    return null;
  }

  Map<String, dynamic>? get _resultData {
    if (!_isResult) return null;
    final meta = message.metadata;
    if (meta == null) return null;
    final r = meta['tool_result'];
    if (r is Map<String, dynamic>) return r;
    if (r is Map) {
      return r.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  /// Live execution status streamed by the backend
  /// ({status: started|finished, duration_ms?}).
  Map<String, dynamic>? get _execution {
    final raw = message.metadata?['tool_execution'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  String get _toolName {
    if (_isCall) {
      final data = _callData;
      if (data != null) {
        final n = data['name'];
        if (n is String && n.isNotEmpty) return n;
      }
    }
    if (_isResult) {
      final data = _resultData;
      if (data != null) {
        final n = data['tool_name'];
        if (n is String && n.isNotEmpty) return n;
      }
    }
    return message.content.isNotEmpty ? message.content : 'tool';
  }

  String _pretty(Object? value) {
    if (value == null) return 'null';
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  /// Render args/result as a compact one-line preview shown next to the title.
  String _summary(Object? value, {int max = 80}) {
    if (value == null) return '';
    String s;
    if (value is String) {
      s = value;
    } else if (value is Map) {
      if (value.isEmpty) return '';
      final parts = value.entries.map((e) {
        final v = e.value;
        final vs = (v is String) ? '"$v"' : v.toString();
        return '${e.key}: $vs';
      });
      s = parts.join(', ');
    } else if (value is List) {
      s = value.map((e) => e.toString()).join(', ');
    } else {
      s = value.toString();
    }
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > max) s = '${s.substring(0, max - 1)}…';
    return s;
  }

  bool _isErrorResult() {
    final r = _resultData?['result'];
    if (r is Map) {
      if (r['ok'] == false) return true;
      if (r['is_error'] == true) return true;
    }
    return false;
  }

  /// Live status trailer for tool calls: spinner + "running…" while the
  /// backend executes, "done in X.Xs" once the finished marker arrives.
  List<Widget> _buildStatus(ThemeData theme, ColorScheme colorScheme) {
    if (!_isCall) return const [];
    final execution = _execution;
    final status = execution?['status'];
    final dim = colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    if (status == 'finished') {
      final ms = execution?['duration_ms'];
      final label = ms is num
          ? 'done in ${(ms / 1000).toStringAsFixed(1)}s'
          : 'done';
      return [
        const SizedBox(width: 8),
        Icon(Icons.check, size: 12, color: dim),
        const SizedBox(width: 3),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: dim)),
      ];
    }

    if (status == 'started' || widget.isStreaming) {
      return [
        const SizedBox(width: 8),
        SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: colorScheme.primary,
          ),
        ),
        if (status == 'started') ...[
          const SizedBox(width: 5),
          Text(
            'running…',
            style: theme.textTheme.labelSmall?.copyWith(color: dim),
          ),
        ],
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final callData = _callData;
    final resultData = _resultData;
    final args = callData?['arguments'];
    final result = resultData?['result'];

    final isError = _isResult && _isErrorResult();
    final accent = isError ? colorScheme.error : colorScheme.onSurfaceVariant;

    final IconData glyph;
    if (_isCall) {
      glyph = Icons.arrow_outward;
    } else if (isError) {
      glyph = Icons.error_outline;
    } else {
      glyph = Icons.subdirectory_arrow_right;
    }

    final preview = _isCall
        ? _summary(args)
        : _summary(result is Map ? (result['content'] ?? result) : result);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            hoverColor: colorScheme.onSurface.withValues(alpha: 0.03),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(glyph, size: 13, color: accent.withValues(alpha: 0.8)),
                  const SizedBox(width: 8),
                  Text(
                    _isCall ? 'call' : (isError ? 'error' : 'result'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _toolName,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: isError
                            ? colorScheme.error
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 3,
                      child: Text(
                        preview,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.65,
                          ),
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                  ..._buildStatus(theme, colorScheme),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.expand_more,
                      size: 15,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Expanded payload is only mounted when open, so collapsed rows stay
        // cheap even for very large tool outputs.
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isCall && args != null)
                          _JsonBlock(label: 'Input', text: _pretty(args)),
                        if (_isResult && result != null)
                          _JsonBlock(label: 'Output', text: _pretty(result)),
                        if (!_isCall && !_isResult)
                          _JsonBlock(
                            label: 'Details',
                            text: _pretty(message.metadata),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
