import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../models/chat_attachment.dart';
import '../services/audio_service.dart';

/// Widget for the chat text input field with optional file attachments.
class ChatInputWidget extends StatefulWidget {
  const ChatInputWidget({
    super.key,
    required this.onSend,
    this.onStop,
    this.isLoading = false,
    this.hintText = 'Type a message...',
  });

  final void Function(String message, List<ChatAttachment> attachments) onSend;

  /// Called when the user presses the stop button during streaming.
  final VoidCallback? onStop;

  final bool isLoading;
  final String hintText;

  @override
  State<ChatInputWidget> createState() => _ChatInputWidgetState();
}

class _ChatInputWidgetState extends State<ChatInputWidget> {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode;
  bool _isComposing = false;
  final List<ChatAttachment> _attachments = [];

  // Voice recording state
  AudioRecorder? _recorder;
  bool _isRecording = false;
  bool _isTranscribing = false;
  Timer? _recordingTimer;
  int _recordingDuration = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _recordingTimer?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  bool get _canSend =>
      (_isComposing || _attachments.isNotEmpty) && !widget.isLoading;

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

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      _recorder = AudioRecorder();
      final hasPermission = await _recorder!.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
        _recorder?.dispose();
        _recorder = null;
        return;
      }

      final tempPath =
          '${Directory.systemTemp.path}/garbanzo_voice_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _recorder!.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: tempPath,
      );

      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordingDuration++);
      });
    } catch (e) {
      _recorder?.dispose();
      _recorder = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      final path = await _recorder?.stop();
      _recorder?.dispose();
      _recorder = null;

      setState(() => _isRecording = false);

      if (path == null) return;

      setState(() => _isTranscribing = true);

      final file = File(path);
      final audioBytes = await file.readAsBytes();
      final filename = path.split('/').last;

      final transcript =
          await AudioService.instance.transcribeAudio(audioBytes, filename);

      if (mounted) {
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
          '$prefix$transcript',
        );
        _controller.text = newText;
        _controller.selection = TextSelection.collapsed(
          offset: insertPos + prefix.length + transcript.length,
        );
        _handleTextChange(_controller.text);
      }

      // Clean up temp file
      try {
        await file.delete();
      } catch (_) {}
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

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: [
        // images
        'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp',
        // documents
        'txt', 'md', 'csv', 'json', 'xml', 'yaml', 'yml',
        'html', 'htm', 'css', 'js', 'ts', 'py', 'dart', 'rs',
        'go', 'java', 'kt', 'swift', 'c', 'cpp', 'h',
        'pdf',
      ],
    );

    if (result == null) return;

    const maxFileSize = 10 * 1024 * 1024; // 10 MB
    final added = <ChatAttachment>[];
    final rejected = <String>[];

    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;

      if (bytes.length > maxFileSize) {
        rejected.add(file.name);
        continue;
      }

      final mime = _inferMime(file.name, bytes);
      added.add(ChatAttachment.fromPicked(
        name: file.name,
        mimeType: mime,
        bytes: bytes,
      ));
    }

    if (rejected.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Files exceed 10 MB limit: ${rejected.join(', ')}',
          ),
        ),
      );
    }

    if (added.isNotEmpty) {
      setState(() => _attachments.addAll(added));
    }
  }

  String _inferMime(String filename, Uint8List bytes) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.xml')) return 'application/xml';
    return 'text/plain';
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
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
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_attachments.isNotEmpty) ...[
              _AttachmentPreviewBar(
                attachments: _attachments,
                onRemove: _removeAttachment,
                colorScheme: colorScheme,
                textTheme: theme.textTheme,
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attach button
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: IconButton(
                    onPressed: widget.isLoading ? null : _pickFiles,
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'Attach file',
                    style: IconButton.styleFrom(
                      foregroundColor: colorScheme.onSurfaceVariant,
                      minimumSize: const Size(40, 40),
                    ),
                  ),
                ),
                // Mic button
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _isTranscribing
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          onPressed:
                              widget.isLoading ? null : _toggleRecording,
                          icon:
                              Icon(_isRecording ? Icons.stop : Icons.mic),
                          tooltip: _isRecording
                              ? 'Stop recording'
                              : 'Voice input',
                          style: IconButton.styleFrom(
                            foregroundColor: _isRecording
                                ? colorScheme.error
                                : colorScheme.onSurfaceVariant,
                            minimumSize: const Size(40, 40),
                          ),
                        ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
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
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: colorScheme.error
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _PulsingDot(color: colorScheme.error),
                                const SizedBox(width: 8),
                                Text(
                                  'Recording ${_formatDuration(_recordingDuration)}',
                                  style:
                                      theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onErrorContainer,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
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
                          onPressed: _canSend ? _handleSubmitted : null,
                          icon: const Icon(Icons.send),
                          style: IconButton.styleFrom(
                            backgroundColor: _canSend
                                ? colorScheme.primary
                                : colorScheme.surfaceContainerHighest,
                            foregroundColor: _canSend
                                ? colorScheme.onPrimary
                                : colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.5),
                            minimumSize: const Size(48, 48),
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

/// Pulsing red dot to indicate active recording.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.5 + _controller.value * 0.5),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

/// Horizontal scrollable row of attachment preview chips shown above the input.
class _AttachmentPreviewBar extends StatelessWidget {
  const _AttachmentPreviewBar({
    required this.attachments,
    required this.onRemove,
    required this.colorScheme,
    required this.textTheme,
  });

  final List<ChatAttachment> attachments;
  final void Function(int index) onRemove;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final att = attachments[i];
          return _AttachmentChip(
            attachment: att,
            onRemove: () => onRemove(i),
            colorScheme: colorScheme,
            textTheme: textTheme,
          );
        },
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.onRemove,
    required this.colorScheme,
    required this.textTheme,
  });

  final ChatAttachment attachment;
  final VoidCallback onRemove;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: attachment.isImage
                ? Image.memory(
                    attachment.bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) =>
                        _docIcon(colorScheme, textTheme),
                  )
                : _docIcon(colorScheme, textTheme),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: colorScheme.error,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: 12,
                color: colorScheme.onError,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _docIcon(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.insert_drive_file_outlined,
          size: 24,
          color: colorScheme.primary,
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            attachment.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              fontSize: 8,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
