import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:garbanzo_ai/core/reading_column.dart';

/// Shared chrome for posting a message: a framed multi-line text field with
/// Enter-to-send / Shift+Enter-for-newline handling, plus a send/stop button.
///
/// Used by both the main chat ([ChatInputWidget], which wraps this with
/// attachments and voice recording) and rooms (`RoomChatPage`, which uses it
/// bare) so the two composers look and behave identically. App-specific
/// extras plug in via slots:
///   - [leading]: widget placed before the text field (e.g. attach button).
///   - [overlay]: widget stacked over the text field (e.g. recording banner).
///   - [above]: widget placed above the input row (e.g. attachment preview).
///   - [idleTrailingBuilder]: replaces the default disabled send button when
///     there's nothing to send and no stream is loading (e.g. a voice-input
///     mic button).
///
/// [controller] / [focusNode] may be supplied so a caller can manipulate the
/// text directly (paste, inserting a voice transcript) — the composer
/// listens to whichever controller it ends up with to keep its send-button
/// state in sync.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.onSend,
    this.controller,
    this.focusNode,
    this.onStop,
    this.isLoading = false,
    this.enabled = true,
    this.hintText = 'Type a message...',
    this.hasExtraContent = false,
    this.leading,
    this.overlay,
    this.above,
    this.idleTrailingBuilder,
    this.onChanged,
    this.onBlur,
  });

  final ValueChanged<String> onSend;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Called whenever the field's text changes. Optional — used by rooms to
  /// drive a debounced typing indicator; chat leaves it null (no behaviour
  /// change).
  final ValueChanged<String>? onChanged;

  /// Called when the field loses focus. Optional — rooms use it to clear the
  /// typing indicator.
  final VoidCallback? onBlur;

  /// Called when the user presses the stop button during streaming.
  final VoidCallback? onStop;

  final bool isLoading;

  /// Disables the whole composer (e.g. room not loaded yet).
  final bool enabled;
  final String hintText;

  /// Whether there's send-worthy content outside the text field itself
  /// (e.g. attachments), so the send button enables even with empty text.
  final bool hasExtraContent;

  final Widget? leading;
  final Widget? overlay;
  final Widget? above;
  final WidgetBuilder? idleTrailingBuilder;

  @override
  State<MessageComposer> createState() => MessageComposerState();
}

class MessageComposerState extends State<MessageComposer> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  late final FocusNode _focusNode =
      widget.focusNode ?? FocusNode(onKeyEvent: _handleKeyEvent);
  bool _isComposing = false;

  bool get _canSend =>
      (_isComposing || widget.hasExtraContent) && widget.enabled;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleControllerChanged);
    // If an externally-owned FocusNode was supplied, it may not have been
    // wired up with our key handler.
    if (widget.focusNode != null) {
      widget.focusNode!.onKeyEvent = _handleKeyEvent;
    }
    if (widget.onBlur != null) _focusNode.addListener(_handleFocusChanged);
    _isComposing = _controller.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    if (widget.onBlur != null) _focusNode.removeListener(_handleFocusChanged);
    if (widget.controller == null) _controller.dispose();
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    widget.onChanged?.call(_controller.text);
    final isComposing = _controller.text.trim().isNotEmpty;
    if (isComposing != _isComposing) {
      setState(() => _isComposing = isComposing);
    }
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) widget.onBlur?.call();
  }

  /// Submits the current text (if any) via [MessageComposer.onSend], then
  /// clears the field. Exposed so callers holding a
  /// `GlobalKey<MessageComposerState>` can trigger a submit programmatically
  /// (e.g. auto-submit after a voice transcription).
  void submit() {
    final text = _controller.text.trim();
    if (!_canSend) return;
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (HardwareKeyboard.instance.isControlPressed &&
        event.logicalKey == LogicalKeyboardKey.keyV) {
      _handlePaste();
      return KeyEventResult.handled;
    }

    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;

    if (HardwareKeyboard.instance.isShiftPressed) {
      final sel = _controller.selection;
      final text = _controller.text;
      final newText = text.replaceRange(sel.start, sel.end, '\n');
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + 1),
      );
    } else {
      submit();
    }
    return KeyEventResult.handled;
  }

  Future<void> _handlePaste() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData?.text != null) {
      final sel = _controller.selection;
      final text = _controller.text;
      final newText = text.replaceRange(
        sel.start,
        sel.end,
        clipboardData!.text!,
      );
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(
        offset: sel.start + clipboardData.text!.length,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 4 : 12,
        vertical: isMobile ? 2 : 8,
      ),
      child: SafeArea(
        top: false,
        // Match the message list's centered reading column so the composer
        // lines up with the conversation above it.
        child: ReadingColumn(
          horizontalPadding: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.above != null) ...[
                widget.above!,
                const SizedBox(height: 8),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (widget.leading != null)
                    Padding(
                      padding: EdgeInsets.only(right: isMobile ? 0 : 8),
                      child: widget.leading!,
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(
                              isMobile ? 16 : 20,
                            ),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: isMobile ? 100 : 150,
                            ),
                            child: TextField(
                              key: const ValueKey('message_input'),
                              controller: _controller,
                              focusNode: _focusNode,
                              enabled: widget.enabled,
                              maxLines: null,
                              minLines: 1,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: widget.hintText,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: isMobile ? 10 : 12,
                                  vertical: isMobile ? 8 : 10,
                                ),
                                border: InputBorder.none,
                                hintStyle: TextStyle(
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ),
                        if (widget.overlay != null)
                          Positioned.fill(child: widget.overlay!),
                      ],
                    ),
                  ),
                  SizedBox(width: isMobile ? 4 : 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: _buildTrailingButton(colorScheme, isMobile),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrailingButton(ColorScheme colorScheme, bool isMobile) {
    if (widget.isLoading) {
      return IconButton.filled(
        key: const ValueKey('stop_button'),
        onPressed: widget.onStop,
        icon: const Icon(Icons.stop_rounded, size: 20),
        tooltip: 'Stop generation',
        style: IconButton.styleFrom(
          backgroundColor: colorScheme.error,
          foregroundColor: colorScheme.onError,
          minimumSize: Size(isMobile ? 32 : 40, isMobile ? 32 : 40),
          padding: EdgeInsets.zero,
        ),
        constraints: BoxConstraints(
          minWidth: isMobile ? 32 : 40,
          minHeight: isMobile ? 32 : 40,
        ),
      );
    }
    if (_canSend) {
      return IconButton.filled(
        key: const ValueKey('send_button'),
        onPressed: submit,
        icon: Icon(Icons.send, size: isMobile ? 18 : 20),
        tooltip: 'Send message',
        style: IconButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: Size(isMobile ? 32 : 40, isMobile ? 32 : 40),
          padding: EdgeInsets.zero,
        ),
        constraints: BoxConstraints(
          minWidth: isMobile ? 32 : 40,
          minHeight: isMobile ? 32 : 40,
        ),
      );
    }
    if (widget.idleTrailingBuilder != null) {
      return widget.idleTrailingBuilder!(context);
    }
    return IconButton.filled(
      key: const ValueKey('send_button'),
      tooltip: 'Send message',
      onPressed: null,
      icon: Icon(Icons.send, size: isMobile ? 18 : 20),
      style: IconButton.styleFrom(
        backgroundColor: colorScheme.surfaceContainerHighest,
        foregroundColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        minimumSize: Size(isMobile ? 32 : 40, isMobile ? 32 : 40),
        padding: EdgeInsets.zero,
      ),
      constraints: BoxConstraints(
        minWidth: isMobile ? 32 : 40,
        minHeight: isMobile ? 32 : 40,
      ),
    );
  }
}
