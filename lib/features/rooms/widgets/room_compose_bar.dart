import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Compose bar for posting to a room.
///
/// Visually mirrors the main chat ChatInputWidget — multi-line text field
/// with a circular send button — but stripped of attachments / voice since
/// the room model doesn't currently support them.
class RoomComposeBar extends StatefulWidget {
  const RoomComposeBar({
    super.key,
    required this.onSend,
    this.hintText = 'Message the room… (use @AgentName or @all)',
    this.enabled = true,
  });

  final ValueChanged<String> onSend;
  final String hintText;
  final bool enabled;

  @override
  State<RoomComposeBar> createState() => _RoomComposeBarState();
}

class _RoomComposeBarState extends State<RoomComposeBar> {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode;
  bool _isComposing = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _onKey);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    _submit();
    return KeyEventResult.handled;
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    widget.onSend(text);
    _controller.clear();
    setState(() => _isComposing = false);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withOpacity(0.6),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: widget.enabled,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    onChanged: (v) {
                      final composing = v.trim().isNotEmpty;
                      if (composing != _isComposing) {
                        setState(() => _isComposing = composing);
                      }
                    },
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: widget.hintText,
                      hintStyle: TextStyle(
                        color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                      ),
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SendButton(
                enabled: widget.enabled && _isComposing,
                onPressed: _submit,
                colorScheme: colorScheme,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.onPressed,
    required this.colorScheme,
  });

  final bool enabled;
  final VoidCallback onPressed;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? colorScheme.primary : colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onPressed : null,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            Icons.send_rounded,
            color: enabled
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant.withOpacity(0.5),
            size: 20,
          ),
        ),
      ),
    );
  }
}
