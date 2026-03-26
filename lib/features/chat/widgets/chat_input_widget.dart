import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../settings/providers/settings_provider.dart';
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

  // Voice recording state
  AudioRecorder? _recorder;
  Process? _arecordProcess;
  String? _arecordPath;
  bool _isRecording = false;
  bool _isTranscribing = false;
  Timer? _recordingTimer;
  int _recordingDuration = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    // Pre-load attachments from drag-and-drop
    if (widget.initialAttachments != null) {
      _attachments.addAll(widget.initialAttachments!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _recordingTimer?.cancel();
    _recorder?.dispose();
    _arecordProcess?.kill();
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

    // Handle Ctrl+V for paste
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

  /// Handle paste from clipboard - text only.
  /// Image paste requires platform-specific implementation.
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

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  /// Check whether a binary is available on this system.
  Future<bool> _hasBinary(String name) async {
    try {
      final result = await Process.run('which', [name]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Find the best ALSA capture card by parsing `arecord -l`.
  ///
  /// Returns the card number (e.g. "2") of a real microphone, preferring
  /// webcam/built-in over docking-station devices.
  Future<String?> _findAlsaCaptureCard() async {
    try {
      final result = await Process.run('arecord', ['-l']);
      if (result.exitCode != 0) return null;

      final output = result.stdout as String;
      // Lines like: "card 2: Webcam [NexiGo N660P FHD Webcam], device 0: ..."
      final lineRe = RegExp(r'card\s+(\d+):\s+\S+\s+\[(.+?)\]');

      String? bestCard;
      String? firstCard;

      for (final match in lineRe.allMatches(output)) {
        final cardNum = match.group(1)!;
        final name = match.group(2)!.toLowerCase();

        firstCard ??= cardNum;

        // Skip docking stations — these often have no actual mic
        if (name.contains('dock') || name.contains('hdmi')) continue;

        bestCard ??= cardNum;
      }

      return bestCard ?? firstCard;
    } catch (_) {
      return null;
    }
  }

  Future<void> _startRecording() async {
    final tempPath =
        '${Directory.systemTemp.path}/garbanzo_voice_${DateTime.now().millisecondsSinceEpoch}.wav';

    // Use arecord with direct ALSA hardware access (bypasses PipeWire routing
    // issues where the wrong default source captures silence).
    if (await _hasBinary('arecord')) {
      try {
        final card = await _findAlsaCaptureCard();
        final device = card != null ? 'plughw:$card,0' : 'default';
        _arecordPath = tempPath;
        _arecordProcess = await Process.start('arecord', [
          '-D', device,
          '-f', 'S16_LE',
          '-r', '44100',
          '-c', '1',
          tempPath,
        ]);
      } catch (e) {
        _arecordProcess = null;
        _arecordPath = null;
      }
    }

    // Fallback: try the record package (uses parecord → PulseAudio/PipeWire)
    if (_arecordProcess == null && await _hasBinary('parecord')) {
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

        await _recorder!.start(
          const RecordConfig(encoder: AudioEncoder.wav),
          path: tempPath,
        );
      } catch (_) {
        _recorder?.dispose();
        _recorder = null;
      }
    }

    if (_arecordProcess == null && _recorder == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone not available. Install alsa-utils or pulseaudio-utils.')),
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

    String? path;

    try {
      // Stop whichever recording method is active
      if (_arecordProcess != null) {
        _arecordProcess!.kill(ProcessSignal.sigint);
        await _arecordProcess!.exitCode;
        path = _arecordPath;
        _arecordProcess = null;
        _arecordPath = null;
      } else {
        path = await _recorder?.stop();
        _recorder?.dispose();
        _recorder = null;
      }

      setState(() => _isRecording = false);

      if (path == null) return;

      setState(() => _isTranscribing = true);

      final file = File(path);
      final audioBytes = await file.readAsBytes();
      final filename = path.split('/').last;

      final transcript =
          await AudioService.instance.transcribeAudio(audioBytes, filename);

      if (mounted) {
        if (transcript.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No speech detected. Check that your microphone is set as '
                'the default input device.',
              ),
            ),
          );
        } else {
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

        // Auto-submit if the setting is enabled
        final settings = context.read<SettingsProvider>();
        if (settings.autoSubmitStt && transcript.trim().isNotEmpty) {
          // Short delay so the user can see the transcribed text
          await Future.delayed(const Duration(milliseconds: 200));
          if (mounted) _handleSubmitted();
        }
        } // end else (transcript not empty)
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
        'pdf', 'xlsx', 'xls', 'ods',
      ],
    );

    if (result == null) return;

    final added = <ChatAttachment>[];
    final rejected = <String>[];
    final validationErrors = <String>[];

    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;

      // Validate file size based on type
      final mime = _inferMime(file.name, bytes);
      final isImage = mime.startsWith('image/');
      final isPdf = mime == 'application/pdf';
      final isSpreadsheet = mime.endsWith('spreadsheetml.sheet') ||
          mime == 'application/vnd.ms-excel' ||
          mime == 'application/vnd.oasis.opendocument.spreadsheet' ||
          file.name.toLowerCase().endsWith('.csv') ||
          file.name.toLowerCase().endsWith('.xlsx') ||
          file.name.toLowerCase().endsWith('.xls') ||
          file.name.toLowerCase().endsWith('.ods');

      final maxBytes = isImage
          ? 5 * 1024 * 1024 // 5 MB for images
          : isPdf
              ? 20 * 1024 * 1024 // 20 MB for PDFs
              : isSpreadsheet
                  ? 10 * 1024 * 1024 // 10 MB for spreadsheets/CSV
                  : 10 * 1024 * 1024; // 10 MB for other documents

      if (bytes.length > maxBytes) {
        rejected.add('${file.name} (${_formatBytes(bytes.length)} - max ${_formatBytes(maxBytes)})');
        continue;
      }

      // Check for duplicate filenames
      if (_attachments.any((a) => a.name == file.name)) {
        validationErrors.add('Duplicate file: ${file.name}');
        continue;
      }

      added.add(ChatAttachment.fromPicked(
        name: file.name,
        mimeType: mime,
        bytes: bytes,
      ));
    }

    // Show validation errors
    if (validationErrors.isNotEmpty && mounted) {
      for (final error in validationErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    }

    // Show rejection errors
    if (rejected.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Files too large:\n${rejected.join('\n')}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (added.isNotEmpty) {
      setState(() => _attachments.addAll(added));
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
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
