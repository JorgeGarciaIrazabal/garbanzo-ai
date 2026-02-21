import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Widget for the chat text input field.
class ChatInputWidget extends StatefulWidget {
  const ChatInputWidget({
    super.key,
    required this.onSend,
    this.onStop,
    this.isLoading = false,
    this.hintText = 'Type a message...',
  });

  final ValueChanged<String> onSend;

  /// Called when the user presses the stop button during streaming.
  final VoidCallback? onStop;

  final bool isLoading;
  final String hintText;

  @override
  State<ChatInputWidget> createState() => _ChatInputWidgetState();
}

class _ChatInputWidgetState extends State<ChatInputWidget> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isComposing = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSubmitted() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isLoading) return;

    widget.onSend(text);
    _controller.clear();
    setState(() => _isComposing = false);
    _focusNode.requestFocus();
  }

  void _handleTextChange(String text) {
    final isComposing = text.trim().isNotEmpty;
    if (_isComposing != isComposing) {
      setState(() => _isComposing = isComposing);
    }
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Text input field
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: KeyboardListener(
                    focusNode: FocusNode(),
                    onKeyEvent: (event) {
                      if (event is! KeyDownEvent) return;
                      final isEnter =
                          event.logicalKey == LogicalKeyboardKey.enter ||
                              event.logicalKey == LogicalKeyboardKey.numpadEnter;
                      if (!isEnter) return;

                      if (HardwareKeyboard.instance.isShiftPressed) {
                        // Shift+Enter: insert a newline at cursor
                        final sel = _controller.selection;
                        final text = _controller.text;
                        final newText =
                            text.replaceRange(sel.start, sel.end, '\n');
                        _controller.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection.collapsed(
                              offset: sel.start + 1),
                        );
                        setState(
                            () => _isComposing = newText.trim().isNotEmpty);
                      } else {
                        // Enter: send message
                        _handleSubmitted();
                      }
                    },
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      onChanged: _handleTextChange,
                      maxLines: null,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                          color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                        ),
                      ),
                      style: theme.textTheme.bodyMedium,
                      enabled: !widget.isLoading,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Send / Stop button
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: widget.isLoading
                  ? IconButton.filled(
                      onPressed: widget.onStop,
                      icon: const Icon(Icons.stop_rounded),
                      tooltip: 'Stop generation',
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        foregroundColor: colorScheme.onError,
                        minimumSize: const Size(48, 48),
                      ),
                    )
                  : IconButton.filled(
                      onPressed: _isComposing ? _handleSubmitted : null,
                      icon: const Icon(Icons.send),
                      style: IconButton.styleFrom(
                        backgroundColor: _isComposing
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                        foregroundColor: _isComposing
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant.withOpacity(0.5),
                        minimumSize: const Size(48, 48),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
