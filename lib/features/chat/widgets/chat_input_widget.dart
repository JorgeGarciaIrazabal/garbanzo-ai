import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../settings/providers/settings_provider.dart';
import '../models/chat_attachment.dart';
import 'input/attachment_preview.dart';
import 'input/file_picker_helper.dart';
import 'input/pulsing_dot.dart';
import 'input/voice_recording_helper.dart';

/// Widget for the chat text input field with optional file attachments.
class ChatInputWidget extends StatefulWidget {
  const ChatInputWidget({
    super.key,
    required this.onSend,
    this.onStop,
    this.isLoading = false,
    this.hintText = 'Type a message...',
    this.initialAttachments,
  });

  final void Function(String message, List<ChatAttachment> attachments) onSend;

  /// Called when the user presses the stop button during streaming.
  final VoidCallback? onStop;

  final bool isLoading;
  final String hintText;

  /// Pre-loaded attachments (e.g., from drag-and-drop).
  final List<ChatAttachment>? initialAttachments;

  @override
  State<ChatInputWidget> createState() => _ChatInputWidgetState();
}

class _ChatInputWidgetState extends State<ChatInputWidget> {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode;
  bool _isComposing = false;
  final List<ChatAttachment> _attachments = [];

  // Voice recording
  final VoiceRecordingHelper _voiceHelper = VoiceRecordingHelper();
  bool _isRecording = false;
  bool _isTranscribing = false;
  Timer? _recordingTimer;
  int _recordingDuration = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    if (widget.initialAttachments != null) {
      _attachments.addAll(widget.initialAttachments!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _recordingTimer?.cancel();
    _voiceHelper.dispose();
    super.dispose();
  }

  bool get _canSend =>
      (_isComposing || _attachments.isNotEmpty) && !widget.isLoading;

  // -- Text handling ---------------------------------------------------------

  void _handleSubmitted() {
    final text = _controller.text.trim();
    if (!_canSend) return;

    final attachments = List<ChatAttachment>.from(_attachments);
    widget.onSend(text, attachments);
    _controller.clear();
    setState(() {
      _isComposing = false;
      _attachments.clear();
    });
    _focusNode.requestFocus();
  }

  void _handleTextChange(String text) {
    final isComposing = text.trim().isNotEmpty;
    if (_isComposing != isComposing) {
      setState(() => _isComposing = isComposing);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (HardwareKeyboard.instance.isControlPressed &&
        event.logicalKey == LogicalKeyboardKey.keyV) {
      _handlePaste();
      return KeyEventResult.handled;
    }

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
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
      setState(() => _isComposing = newText.trim().isNotEmpty);
    } else {
      _handleSubmitted();
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
      _handleTextChange(newText);
    }
  }

  // -- Voice recording -------------------------------------------------------

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      await _voiceHelper.startRecording();
    } on VoiceRecordingException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return;
    }

    setState(() {
      _isRecording = true;
      _recordingDuration = 0;
    });

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recordingDuration++);
    });
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    setState(() => _isRecording = false);

    try {
      setState(() => _isTranscribing = true);

      final result = await _voiceHelper.stopAndTranscribe();
      if (result == null || !mounted) return;

      if (result.transcript.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No speech detected. Check that your microphone is set as '
              'the default input device.',
            ),
          ),
        );
        return;
      }

      // Insert transcript at cursor position
      final currentText = _controller.text;
      final selection = _controller.selection;
      final insertPos =
          selection.isValid ? selection.baseOffset : currentText.length;
      final prefix = insertPos > 0 && currentText[insertPos - 1] != ' '
          ? ' '
          : '';
      final newText = currentText.replaceRange(
        insertPos,
        insertPos,
        '$prefix${result.transcript}',
      );
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(
        offset: insertPos + prefix.length + result.transcript.length,
      );
      _handleTextChange(_controller.text);

      // Auto-submit if the setting is enabled
      final settings = context.read<SettingsProvider>();
      if (settings.autoSubmitStt && result.transcript.trim().isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) _handleSubmitted();
      }
    } on VoiceRecordingException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transcription failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTranscribing = false);
      }
    }
  }

  // -- File picking ----------------------------------------------------------

  Future<void> _pickFiles() async {
    final result = await FilePickerHelper.pickFiles(
      existingNames: _attachments.map((a) => a.name).toSet(),
    );
    if (result == null) return;

    if (result.validationErrors.isNotEmpty && mounted) {
      for (final error in result.validationErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    }

    if (result.rejected.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Files too large:\n${result.rejected.join('\n')}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (result.added.isNotEmpty) {
      setState(() => _attachments.addAll(result.added));
    }
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  // -- Helpers ---------------------------------------------------------------

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  // -- Build -----------------------------------------------------------------

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_attachments.isNotEmpty) ...[
              AttachmentPreviewBar(
                attachments: _attachments,
                onRemove: _removeAttachment,
                colorScheme: colorScheme,
                textTheme: theme.textTheme,
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Attach file button
                Padding(
                  padding: EdgeInsets.only(right: isMobile ? 0 : 8),
                  child: IconButton(
                    onPressed: widget.isLoading ? null : _pickFiles,
                    icon: const Icon(Icons.attach_file, size: 22),
                    tooltip: 'Attach file',
                    style: IconButton.styleFrom(
                      foregroundColor: colorScheme.onSurfaceVariant,
                      minimumSize: const Size(32, 32),
                      padding: EdgeInsets.zero,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ),
                // Text field with recording overlay
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
                          border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: isMobile ? 100 : 150),
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            onChanged: _handleTextChange,
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
                      if (_isRecording)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer
                                  .withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
                              border: Border.all(
                                color: colorScheme.error
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                PulsingDot(color: colorScheme.error),
                                const SizedBox(width: 6),
                                Text(
                                  'Recording ${_formatDuration(_recordingDuration)}',
                                  style:
                                      theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onErrorContainer,
                                    fontWeight: FontWeight.w500,
                                    fontSize: isMobile ? 12 : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: isMobile ? 4 : 8),
                // Send / Mic / Stop / Transcribing button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: widget.isLoading
                      ? IconButton.filled(
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
                        )
                      : _isTranscribing
                          ? SizedBox(
                              width: isMobile ? 32 : 40,
                              height: isMobile ? 32 : 40,
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _canSend
                              ? IconButton.filled(
                                  onPressed: _handleSubmitted,
                                  icon: Icon(Icons.send, size: isMobile ? 18 : 20),
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
                                )
                              : IconButton(
                                  onPressed: _toggleRecording,
                                  icon: Icon(
                                    _isRecording ? Icons.stop : Icons.mic,
                                    size: isMobile ? 20 : 22,
                                  ),
                                  tooltip: _isRecording ? 'Stop recording' : 'Voice input',
                                  style: IconButton.styleFrom(
                                    foregroundColor: _isRecording
                                        ? colorScheme.error
                                        : colorScheme.onSurfaceVariant,
                                    minimumSize: Size(isMobile ? 32 : 40, isMobile ? 32 : 40),
                                    padding: EdgeInsets.zero,
                                  ),
                                  constraints: BoxConstraints(
                                    minWidth: isMobile ? 32 : 40,
                                    minHeight: isMobile ? 32 : 40,
                                  ),
                                ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
