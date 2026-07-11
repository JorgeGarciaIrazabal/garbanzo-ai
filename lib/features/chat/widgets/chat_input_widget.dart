import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../settings/providers/settings_provider.dart';
import '../models/chat_attachment.dart';
import 'input/attachment_preview.dart';
import 'input/file_picker_helper.dart';
import 'input/message_composer.dart';
import 'input/pulsing_dot.dart';
import 'input/voice_recording_helper.dart';

/// Widget for the chat text input field with optional file attachments.
///
/// Wraps the shared [MessageComposer] chrome with chat-specific extras: an
/// attach-file button, an attachment preview bar, and voice recording.
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
  final FocusNode _focusNode = FocusNode();
  final GlobalKey<MessageComposerState> _composerKey = GlobalKey();
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

  // -- Sending -----------------------------------------------------------------

  void _handleSend(String text) {
    final attachments = List<ChatAttachment>.from(_attachments);
    widget.onSend(text, attachments);
    setState(() => _attachments.clear());
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

      // Insert transcript at cursor position. MessageComposer listens to
      // this controller directly, so its send-button state updates itself.
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

      // Auto-submit if the setting is enabled
      final settings = context.read<SettingsProvider>();
      if (settings.autoSubmitStt && result.transcript.trim().isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) _composerKey.currentState?.submit();
      }
    } on VoiceRecordingException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (kDebugMode) print('Transcription failed: $e');
      if (mounted) {
        // Map raw failures to actionable messages instead of dumping the
        // exception at the user.
        final raw = e.toString();
        final String message;
        if (raw.contains('SocketException') ||
            raw.contains('Connection') ||
            raw.contains('timed out')) {
          message =
              'Could not reach the server — check your connection and try again.';
        } else if (raw.contains('500') ||
            raw.contains('503') ||
            raw.contains('unavailable')) {
          message = 'Speech-to-text is currently unavailable on the server.';
        } else {
          message = 'Transcription failed — please try again.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
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

    return MessageComposer(
      key: _composerKey,
      controller: _controller,
      focusNode: _focusNode,
      onSend: _handleSend,
      onStop: widget.onStop,
      isLoading: widget.isLoading,
      hintText: widget.hintText,
      hasExtraContent: _attachments.isNotEmpty,
      above: _attachments.isEmpty
          ? null
          : AttachmentPreviewBar(
              attachments: _attachments,
              onRemove: _removeAttachment,
              colorScheme: colorScheme,
              textTheme: theme.textTheme,
            ),
      leading: IconButton(
        key: const ValueKey('attach_button'),
        onPressed: widget.isLoading ? null : _pickFiles,
        icon: const Icon(Icons.attach_file, size: 22),
        tooltip: 'Attach file',
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurfaceVariant,
          minimumSize: const Size(32, 32),
          padding: EdgeInsets.zero,
        ),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
      overlay: !_isRecording
          ? null
          : Container(
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PulsingDot(color: colorScheme.error),
                  const SizedBox(width: 6),
                  Text(
                    'Recording ${_formatDuration(_recordingDuration)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w500,
                      fontSize: isMobile ? 12 : null,
                    ),
                  ),
                ],
              ),
            ),
      idleTrailingBuilder: (_) => _isTranscribing
          ? SizedBox(
              width: isMobile ? 32 : 40,
              height: isMobile ? 32 : 40,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : IconButton(
              key: const ValueKey('voice_button'),
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
    );
  }
}
