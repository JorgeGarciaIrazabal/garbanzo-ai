import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import 'tool_bubble_widget.dart';

/// A run of consecutive `tool_call` / `tool_result` messages rendered as a
/// single collapsible section, mirroring the thinking-content UX.
///
/// The header shows progress at a glance ("Calling X…" while streaming, or
/// "Used N tools" once settled). Tapping expands a thin vertical rail with
/// one [ToolBubbleWidget] entry per call/result — a quiet timeline of the
/// work the agent did before answering.
class ToolActivityGroup extends StatefulWidget {
  const ToolActivityGroup({
    super.key,
    required this.messages,
    this.isStreaming = false,
  });

  /// Ordered run of tool_call / tool_result messages.
  final List<ChatMessage> messages;

  /// True when this group is the trailing group of an in-flight stream and
  /// the last call has no matching result yet.
  final bool isStreaming;

  @override
  State<ToolActivityGroup> createState() => _ToolActivityGroupState();
}

class _ToolActivityGroupState extends State<ToolActivityGroup> {
  bool _isExpanded = false;

  /// Pull the tool name from a single message (best-effort).
  String? _toolName(ChatMessage m) {
    final meta = m.metadata;
    if (meta == null) return null;
    if (m.isToolCall) {
      final list = meta['tool_calls'];
      if (list is List && list.isNotEmpty) {
        final first = list.first;
        if (first is Map) {
          final n = first['name'];
          if (n is String && n.isNotEmpty) return n;
        }
      }
    }
    if (m.isToolResult) {
      final r = meta['tool_result'];
      if (r is Map) {
        final n = r['tool_name'];
        if (n is String && n.isNotEmpty) return n;
      }
    }
    return null;
  }

  /// True when the trailing tool_call has no matching tool_result yet.
  bool _hasPendingCall() {
    if (widget.messages.isEmpty) return false;
    return widget.messages.last.isToolCall;
  }

  /// True when the trailing message is a tool_result and we're still
  /// streaming — i.e. we've finished a tool round and are waiting for the
  /// model to produce its next response.
  bool _waitingForModel() {
    if (widget.messages.isEmpty) return false;
    return widget.isStreaming && widget.messages.last.isToolResult;
  }

  String _headerLabel() {
    final calls = widget.messages.where((m) => m.isToolCall).toList();
    final pending = widget.isStreaming && _hasPendingCall();
    if (pending) {
      final name = _toolName(calls.last) ?? 'tool';
      return 'Calling $name…';
    }
    if (_waitingForModel()) return 'Working on response…';
    if (calls.length == 1) {
      final name = _toolName(calls.first) ?? 'tool';
      return 'Used $name';
    }
    return 'Used ${calls.length} tools';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pending = widget.isStreaming && _hasPendingCall();
    final waiting = _waitingForModel();
    final showSpinner = pending || waiting;
    final live = showSpinner;

    final headerColor = live
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.75);

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              borderRadius: BorderRadius.circular(8),
              hoverColor: colorScheme.onSurface.withValues(alpha: 0.03),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showSpinner)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: colorScheme.primary,
                        ),
                      )
                    else
                      Icon(
                        Icons.construction_outlined,
                        size: 14,
                        color: headerColor,
                      ),
                    const SizedBox(width: 7),
                    Text(
                      _headerLabel(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: headerColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 3),
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: headerColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Container(
              margin: const EdgeInsets.only(left: 12, top: 4),
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < widget.messages.length; i++)
                    ToolBubbleWidget(
                      message: widget.messages[i],
                      // Spinner only on the trailing pending call.
                      isStreaming: pending && i == widget.messages.length - 1,
                    ),
                ],
              ),
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}
