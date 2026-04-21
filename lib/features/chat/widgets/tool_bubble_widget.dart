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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final title = _isCall ? 'Called $_toolName' : 'Result: $_toolName';
    final icon = _isCall ? Icons.build_circle_outlined : Icons.done_all;

    final callData = _callData;
    final resultData = _resultData;

    final args = callData?['arguments'];
    final result = resultData?['result'];

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        child: Card(
          elevation: 0,
          margin: EdgeInsets.only(
            top: 4,
            bottom: 4,
            left: MediaQuery.of(context).size.width * 0.01,
          ),
          color: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: colorScheme.outlineVariant,
              width: 1,
            ),
          ),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            childrenPadding:
                const EdgeInsets.fromLTRB(12, 0, 12, 12),
            leading: Icon(icon,
                size: 18, color: colorScheme.onTertiaryContainer),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
                if (_isCall && isStreaming)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
              ],
            ),
            children: [
              if (_isCall && args != null) ...[
                _SectionLabel(
                  label: 'Input',
                  color: colorScheme.onTertiaryContainer,
                ),
                _JsonBlock(text: _pretty(args)),
              ],
              if (_isResult && result != null) ...[
                _SectionLabel(
                  label: 'Output',
                  color: colorScheme.onTertiaryContainer,
                ),
                _JsonBlock(text: _pretty(result)),
              ],
              if (!_isCall && !_isResult)
                _JsonBlock(text: _pretty(message.metadata)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
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
