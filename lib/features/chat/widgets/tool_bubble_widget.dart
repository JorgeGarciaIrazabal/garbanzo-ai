import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/chat_message.dart';

/// Left-aligned bubble that displays an MCP tool invocation — either the call
/// request (`role: tool_call`) or the server's response (`role: tool_result`).
class ToolBubbleWidget extends StatelessWidget {
  const ToolBubbleWidget({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  final ChatMessage message;

  /// When true and the message is a `tool_call` without a matching result in
  /// this same bubble, shows a spinner indicating the call is running.
  final bool isStreaming;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final callData = _callData;
    final resultData = _resultData;
    final args = callData?['arguments'];
    final result = resultData?['result'];

    final isError = _isResult && _isErrorResult();
    final IconData icon;
    if (_isCall) {
      icon = Icons.build_circle_outlined;
    } else if (isError) {
      icon = Icons.error_outline;
    } else {
      icon = Icons.done_all;
    }

    final preview = _isCall
        ? _summary(args)
        : _summary(result is Map ? (result['content'] ?? result) : result);

    final accent = isError
        ? colorScheme.errorContainer
        : colorScheme.tertiaryContainer;
    final onAccent = isError
        ? colorScheme.onErrorContainer
        : colorScheme.onTertiaryContainer;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        child: Card(
          elevation: 0,
          margin: EdgeInsets.only(
            top: 2,
            bottom: 2,
            left: MediaQuery.of(context).size.width * 0.01,
          ),
          color: accent.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: colorScheme.outlineVariant,
              width: 1,
            ),
          ),
          child: Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              dense: true,
              minTileHeight: 32,
              visualDensity: VisualDensity.compact,
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              childrenPadding:
                  const EdgeInsets.fromLTRB(10, 0, 10, 8),
              leading: Icon(icon, size: 16, color: onAccent),
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _isCall ? 'call' : (isError ? 'error' : 'result'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: onAccent.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _toolName,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: onAccent,
                      ),
                    ),
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      flex: 3,
                      child: Text(
                        preview,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onAccent.withValues(alpha: 0.75),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                  if (_isCall && isStreaming) ...[
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: onAccent,
                      ),
                    ),
                  ],
                ],
              ),
              children: [
                if (_isCall && args != null)
                  _JsonBlock(text: _pretty(args)),
                if (_isResult && result != null)
                  _JsonBlock(text: _pretty(result)),
                if (!_isCall && !_isResult)
                  _JsonBlock(text: _pretty(message.metadata)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}
