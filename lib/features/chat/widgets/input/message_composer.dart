import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:garbanzo_ai/core/reading_column.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Shared chrome for posting a message: a framed multi-line text field with
/// Enter-to-send / Shift+Enter-for-newline handling, plus a send/stop button.
///
/// Used by both the main chat ([ChatInputWidget]) and rooms (`RoomChatView`).
/// Slots: [leading] before field, [overlay] over field, [above] above row,
/// [idleTrailingBuilder] replaces disabled send.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.onStop,
    this.onChanged,
    this.onBlur,
    this.isLoading = false,
    this.enabled = true,
    this.hintText,
    this.hasExtraContent = false,
    this.above,
    this.leading,
    this.overlay,
    this.idleTrailingBuilder,
    this.bottomToolbar,
  });

  final ValueChanged<String> onSend;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onBlur;
  final VoidCallback? onStop;
  final bool isLoading;
  final bool enabled;
  final String? hintText;
  final bool hasExtraContent;
  final Widget? leading;
  final Widget? overlay;
  final Widget? above;
  final WidgetBuilder? idleTrailingBuilder;
  final Widget? bottomToolbar;

  @override
  State<MessageComposer> createState() => MessageComposerState();
}

class MessageComposerState extends State<MessageComposer> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  late final FocusNode _focusNode =
      widget.focusNode ?? FocusNode(onKeyEvent: _handleKeyEvent);
  bool _isComposing = false;
  bool _hasFocus = false;

  bool get _canSend =>
      (_isComposing || widget.hasExtraContent) && widget.enabled;

  static const _mobileBreakpoint = 620.0;
  static double _btnSize(bool m) => m ? 32 : 40;
  static Duration _dur(bool reduce, int ms) =>
      reduce ? Duration.zero : Duration(milliseconds: ms);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleControllerChanged);
    if (widget.focusNode != null) {
      widget.focusNode!.onKeyEvent = _handleKeyEvent;
    }
    _hasFocus = _focusNode.hasFocus;
    _focusNode.addListener(_handleFocusChanged);
    _isComposing = _controller.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _focusNode.removeListener(_handleFocusChanged);
    if (widget.controller == null) _controller.dispose();
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    widget.onChanged?.call(_controller.text);
    final composing = _controller.text.trim().isNotEmpty;
    if (composing != _isComposing) setState(() => _isComposing = composing);
  }

  void _handleFocusChanged() {
    if (_hasFocus != _focusNode.hasFocus) {
      setState(() => _hasFocus = _focusNode.hasFocus);
    }
    if (!_focusNode.hasFocus) widget.onBlur?.call();
  }

  void submit() {
    final text = _controller.text.trim();
    if (!_canSend) return;
    widget.onSend(text);
    _controller.clear();
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        _focusNode.unfocus();
      default:
        _focusNode.requestFocus();
    }
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
      _insertAtSelection('\n');
    } else {
      submit();
    }
    return KeyEventResult.handled;
  }

  void _insertAtSelection(String insert) {
    final sel = _controller.selection;
    final t = _controller.text;
    final newText = t.replaceRange(sel.start, sel.end, insert);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + insert.length),
    );
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null) return;
    final sel = _controller.selection;
    final newText = _controller.text.replaceRange(sel.start, sel.end, text);
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(
      offset: sel.start + text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return LayoutBuilder(
      builder: (context, c) {
        final isMobile = c.maxWidth < _mobileBreakpoint;
        return Container(
          color: cs.surface,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 16,
            vertical: isMobile ? 6 : 10,
          ),
          child: SafeArea(
            top: false,
            child: ReadingColumn(
              horizontalPadding: 0,
              child: AnimatedContainer(
                key: const ValueKey('message_composer_surface'),
                duration: _dur(reduce, 160),
                curve: Curves.easeOut,
                decoration: _surfaceDecoration(cs, isMobile),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.above != null)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          isMobile ? 10 : 14,
                          isMobile ? 10 : 12,
                          isMobile ? 10 : 14,
                          0,
                        ),
                        child: widget.above!,
                      ),
                    if (isMobile)
                      _mobileInputRow(theme, cs, reduce)
                    else
                      _buildEditor(context, theme, cs, isMobile: false),
                    if (isMobile && widget.bottomToolbar != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
                        child: widget.bottomToolbar!,
                      ),
                    if (!isMobile) _desktopBottomBar(reduce, cs),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  BoxDecoration _surfaceDecoration(ColorScheme cs, bool isMobile) =>
      BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(isMobile ? 22 : 26),
        border: Border.all(
          color: _hasFocus
              ? cs.primary.withValues(alpha: 0.65)
              : cs.outlineVariant,
          width: _hasFocus ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: _hasFocus ? 0.10 : 0.05),
            blurRadius: _hasFocus ? 18 : 10,
            offset: const Offset(0, 3),
          ),
        ],
      );

  Widget _mobileInputRow(ThemeData theme, ColorScheme cs, bool reduce) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Row(
        key: const ValueKey('composer_input_row'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.leading != null) widget.leading!,
          if (widget.leading != null) const SizedBox(width: 2),
          Expanded(child: _buildEditor(context, theme, cs, isMobile: true)),
          const SizedBox(width: 2),
          AnimatedContainer(
            duration: _dur(reduce, 200),
            curve: Curves.easeInOut,
            child: _buildTrailingButton(cs, true),
          ),
        ],
      ),
    );
  }

  Widget _desktopBottomBar(bool reduce, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.leading != null) widget.leading!,
          if (widget.bottomToolbar != null) ...[
            const SizedBox(width: 6),
            Expanded(child: widget.bottomToolbar!),
          ] else
            const Spacer(),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: _dur(reduce, 200),
            curve: Curves.easeInOut,
            child: _buildTrailingButton(cs, false),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs, {
    required bool isMobile,
  }) {
    return Stack(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: isMobile ? 96 : 168,
            minHeight: 44,
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
              hintText:
                  widget.hintText ??
                  AppLocalizations.of(context)!.hintTypeAMessage,
              contentPadding: EdgeInsets.symmetric(
                horizontal: isMobile ? 10 : 18,
                vertical: 10,
              ),
              border: InputBorder.none,
              hintStyle: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.62),
              ),
            ),
            style: isMobile
                ? theme.textTheme.bodyMedium
                : theme.textTheme.bodyLarge,
          ),
        ),
        if (widget.overlay != null) Positioned.fill(child: widget.overlay!),
      ],
    );
  }

  Widget _buildTrailingButton(ColorScheme cs, bool isMobile) {
    final s = _btnSize(isMobile);
    final constraints = BoxConstraints(minWidth: s, minHeight: s);
    ButtonStyle style({Color? bg, Color? fg}) => IconButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      minimumSize: Size(s, s),
      padding: EdgeInsets.zero,
    );

    if (widget.isLoading) {
      return IconButton.filled(
        key: const ValueKey('stop_button'),
        onPressed: widget.onStop,
        icon: const Icon(Icons.stop_rounded, size: 20),
        tooltip: 'Stop generation',
        style: style(bg: cs.error, fg: cs.onError),
        constraints: constraints,
      );
    }
    if (_canSend) {
      return IconButton.filled(
        key: const ValueKey('send_button'),
        onPressed: submit,
        icon: Icon(Icons.send, size: isMobile ? 18 : 20),
        tooltip: 'Send message',
        style: style(bg: cs.primary, fg: cs.onPrimary),
        constraints: constraints,
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
      style: style(
        bg: cs.surfaceContainerHighest,
        fg: cs.onSurfaceVariant.withValues(alpha: 0.5),
      ),
      constraints: constraints,
    );
  }
}
