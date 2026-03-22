import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import '../../settings/providers/settings_provider.dart';
import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../services/audio_service.dart';
import '../utils/text_cleaner.dart';
import 'image_viewer.dart';
import 'markdown_widget.dart';
import 'remember_this_button.dart';

/// Widget for displaying a single chat message.
class ChatMessageWidget extends StatefulWidget {
  const ChatMessageWidget({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.conversationId,
  });

  final ChatMessage message;
  final bool isStreaming;
  final String? conversationId;

  @override
  State<ChatMessageWidget> createState() => _ChatMessageWidgetState();
}

class _ChatMessageWidgetState extends State<ChatMessageWidget> {
  bool _metadataExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context.watch<SettingsProvider>();

    final isUser = widget.message.isUser;
    final thinkingContent = _extractThinkingContent();
    final isThinking = widget.isStreaming && thinkingContent != null && widget.message.content.isEmpty;
    final hasMetadata = _hasMetadata();

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          color: isUser
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Message header with role indicator
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUser ? Icons.person : Icons.smart_toy,
                      size: 16,
                      color: isUser
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isUser ? 'You' : 'Assistant',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isUser
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.isStreaming || isThinking) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isUser
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isThinking ? 'Thinking...' : 'Generating...',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isUser
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                // Attachments (images + document chips) for user messages
                if (isUser && widget.message.attachments.isNotEmpty)
                  _AttachmentDisplay(
                    attachments: widget.message.attachments,
                    colorScheme: colorScheme,
                    textTheme: theme.textTheme,
                  ),
                // Thinking content (expandable)
                if (thinkingContent != null && !isUser)
                  _ThinkingContent(
                    thinkingContent: thinkingContent,
                    colorScheme: colorScheme,
                    textTheme: theme.textTheme,
                  ),
                // Message content
                if (widget.message.content.isNotEmpty)
                  _MessageContent(
                    content: widget.message.content,
                    isUser: isUser,
                    colorScheme: colorScheme,
                    textTheme: theme.textTheme,
                  ),
                // Action buttons for assistant messages
                if (!isUser && widget.message.content.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (settings.showMessageMetadata && hasMetadata)
                          _MetadataIconToggle(
                            isExpanded: _metadataExpanded,
                            onToggle: () => setState(() => _metadataExpanded = !_metadataExpanded),
                            colorScheme: colorScheme,
                          ),
                        if (settings.showMessageMetadata && hasMetadata)
                          const SizedBox(width: 8),
                        _CopyButton(content: widget.message.content),
                        const SizedBox(width: 8),
                        _SpeakButton(
                          content: widget.message.content,
                          isStreaming: widget.isStreaming,
                        ),
                      ],
                    ),
                  ),
                  // Expanded metadata details (appears below the row when toggled)
                  if (_metadataExpanded && hasMetadata)
                    _MetadataDetails(
                      metadata: widget.message.metadata!,
                      colorScheme: colorScheme,
                      textTheme: theme.textTheme,
                    ),
                ],
                // Action buttons for user messages
                if (isUser && widget.message.content.isNotEmpty)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CopyButton(content: widget.message.content),
                        const SizedBox(width: 8),
                        RememberThisButton(
                          content: widget.message.content,
                          sourceConversationId: widget.conversationId,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _extractThinkingContent() {
    final metadata = widget.message.metadata;
    if (metadata == null) return null;
    final thinking = metadata['thinking'];
    if (thinking is String && thinking.isNotEmpty) {
      return thinking;
    }
    return null;
  }

  bool _hasMetadata() {
    final metadata = widget.message.metadata;
    if (metadata == null) return false;
    // Check if any relevant metadata fields exist
    // Backend uses: tokens_prompt, tokens_generated, total_duration_ns
    // Also support legacy field names for backwards compatibility
    return metadata.containsKey('tokens_prompt') ||
        metadata.containsKey('input_tokens') ||
        metadata.containsKey('tokens_generated') ||
        metadata.containsKey('output_tokens') ||
        metadata.containsKey('total_duration_ns') ||
        metadata.containsKey('response_time_ms');
  }
}

/// Compact icon button to toggle metadata visibility.
class _MetadataIconToggle extends StatelessWidget {
  const _MetadataIconToggle({
    required this.isExpanded,
    required this.onToggle,
    required this.colorScheme,
  });

  final bool isExpanded;
  final VoidCallback onToggle;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isExpanded ? Icons.info : Icons.info_outline,
              size: 14,
              color: isExpanded
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(
              isExpanded ? 'Hide' : 'Info',
              style: TextStyle(
                fontSize: 12,
                color: isExpanded
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays attached images as thumbnails and documents as chips.
class _AttachmentDisplay extends StatelessWidget {
  const _AttachmentDisplay({
    required this.attachments,
    required this.colorScheme,
    required this.textTheme,
  });

  final List<ChatAttachment> attachments;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final images = attachments.where((a) => a.isImage).toList();
    final docs = attachments.where((a) => a.isDocument).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (images.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: images.map((img) => _ImageThumbnail(img)).toList(),
            ),
          if (docs.isNotEmpty) ...[
            if (images.isNotEmpty) const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: docs.map((doc) => _DocumentChip(doc, colorScheme, textTheme)).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImageThumbnail extends StatefulWidget {
  const _ImageThumbnail(this.attachment);
  final ChatAttachment attachment;

  @override
  State<_ImageThumbnail> createState() => _ImageThumbnailState();
}

class _ImageThumbnailState extends State<_ImageThumbnail> {
  void _openViewer() {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return ImageViewer(
            attachment: widget.attachment,
            onDismiss: () => Navigator.of(context).pop(),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openViewer,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          widget.attachment.bytes,
          width: 160,
          height: 160,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, size: 48),
        ),
      ),
    );
  }
}

class _DocumentChip extends StatelessWidget {
  const _DocumentChip(this.attachment, this.colorScheme, this.textTheme);
  final ChatAttachment attachment;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 14,
            color: colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              attachment.name,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays expandable thinking content.
class _ThinkingContent extends StatefulWidget {
  const _ThinkingContent({
    required this.thinkingContent,
    required this.colorScheme,
    required this.textTheme,
  });

  final String thinkingContent;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  State<_ThinkingContent> createState() => _ThinkingContentState();
}

class _ThinkingContentState extends State<_ThinkingContent> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.psychology_outlined,
                  size: 14,
                  color: widget.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  _isExpanded ? 'Hide thinking' : 'Show thinking',
                  style: widget.textTheme.labelSmall?.copyWith(
                    color: widget.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: widget.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thinking Process',
                  style: widget.textTheme.labelSmall?.copyWith(
                    color: widget.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  widget.thinkingContent,
                  style: widget.textTheme.bodySmall?.copyWith(
                    color: widget.colorScheme.onSurfaceVariant,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Expanded metadata details shown below the action row.
class _MetadataDetails extends StatelessWidget {
  const _MetadataDetails({
    required this.metadata,
    required this.colorScheme,
    required this.textTheme,
  });

  final Map<String, dynamic> metadata;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    // Support both backend field names (tokens_prompt, tokens_generated, total_duration_ns)
    // and legacy field names (input_tokens, output_tokens, response_time_ms)
    final inputTokens = metadata['tokens_prompt'] ?? metadata['input_tokens'];
    final outputTokens = metadata['tokens_generated'] ?? metadata['output_tokens'];
    final totalDurationNs = metadata['total_duration_ns'];
    final responseTimeMs = metadata['response_time_ms'];
    // Calculate total tokens if not provided directly
    final totalTokens = metadata['total_tokens'] ??
        ((inputTokens != null && outputTokens != null)
            ? (inputTokens as num) + (outputTokens as num)
            : null);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          if (inputTokens != null)
            _MetadataItem(
              icon: Icons.input,
              label: 'In',
              value: _formatNumber(inputTokens),
              colorScheme: colorScheme,
            ),
          if (outputTokens != null)
            _MetadataItem(
              icon: Icons.output,
              label: 'Out',
              value: _formatNumber(outputTokens),
              colorScheme: colorScheme,
            ),
          if (totalTokens != null)
            _MetadataItem(
              icon: Icons.token,
              label: 'Total',
              value: _formatNumber(totalTokens),
              colorScheme: colorScheme,
            ),
          if (responseTimeMs != null)
            _MetadataItem(
              icon: Icons.timer_outlined,
              label: 'Time',
              value: _formatDuration(responseTimeMs),
              colorScheme: colorScheme,
            ),
          if (totalDurationNs != null)
            _MetadataItem(
              icon: Icons.timer_outlined,
              label: 'Time',
              value: _formatNanoseconds(totalDurationNs),
              colorScheme: colorScheme,
            ),
        ],
      ),
    );
  }

  String _formatNumber(dynamic value) {
    if (value is int) return value.toString();
    if (value is double) return value.toStringAsFixed(0);
    return value.toString();
  }

  String _formatDuration(dynamic value) {
    double ms;
    if (value is int) {
      ms = value.toDouble();
    } else if (value is double) {
      ms = value;
    } else {
      return value.toString();
    }

    if (ms < 1000) return '${ms.toStringAsFixed(0)}ms';
    final seconds = ms / 1000;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final minutes = seconds / 60;
    return '${minutes.toStringAsFixed(1)}m';
  }

  String _formatNanoseconds(dynamic value) {
    double ns;
    if (value is int) {
      ns = value.toDouble();
    } else if (value is double) {
      ns = value;
    } else {
      return value.toString();
    }

    final ms = ns / 1000000; // Convert nanoseconds to milliseconds
    return _formatDuration(ms);
  }
}

/// A single metadata item displayed inline (icon + label + value).
class _MetadataItem extends StatelessWidget {
  const _MetadataItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 4),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Displays message content with markdown rendering.
class _MessageContent extends StatelessWidget {
  const _MessageContent({
    required this.content,
    required this.isUser,
    required this.colorScheme,
    required this.textTheme,
  });

  final String content;
  final bool isUser;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    if (content.isEmpty) {
      return const SizedBox.shrink();
    }
    return MarkdownWidget(
      content: content,
      colorScheme: colorScheme,
      textTheme: textTheme,
      isSelectable: true,
    );
  }
}

/// Copy button for copying message content.
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.content});

  final String content;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.content));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _copied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: _copy,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _copied ? Icons.check : Icons.copy,
              size: 14,
              color: _copied
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(
              _copied ? 'Copied!' : 'Copy',
              style: TextStyle(
                fontSize: 12,
                color: _copied
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Speak button for TTS playback of assistant messages.
///
/// Reads voice/speed from [SettingsProvider] and cleans markdown/emojis
/// before synthesis. Supports auto-play when streaming finishes.
class _SpeakButton extends StatefulWidget {
  const _SpeakButton({
    required this.content,
    this.isStreaming = false,
  });

  final String content;
  final bool isStreaming;

  @override
  State<_SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<_SpeakButton> {
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _cancelled = false;
  AudioPlayer? _player;

  @override
  void didUpdateWidget(_SpeakButton old) {
    super.didUpdateWidget(old);
    // Auto-play: when streaming transitions from true → false
    if (old.isStreaming && !widget.isStreaming && widget.content.isNotEmpty) {
      final settings = context.read<SettingsProvider>();
      if (settings.autoPlayTts) {
        _speak();
      }
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _player?.dispose();
    super.dispose();
  }

  /// Split text into chunks (~500 chars) at sentence boundaries.
  static List<String> _splitIntoChunks(String text) {
    const targetSize = 500;
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    final chunks = <String>[];
    final buf = StringBuffer();
    for (final sentence in sentences) {
      final trimmed = sentence.trim();
      if (trimmed.isEmpty) continue;
      if (buf.length + trimmed.length > targetSize && buf.isNotEmpty) {
        chunks.add(buf.toString().trim());
        buf.clear();
      }
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(trimmed);
    }
    if (buf.isNotEmpty) chunks.add(buf.toString().trim());
    return chunks.isEmpty ? [text] : chunks;
  }

  Future<void> _speak() async {
    setState(() {
      _isLoading = true;
      _cancelled = false;
    });

    try {
      final settings = context.read<SettingsProvider>();
      final cleaned = cleanTextForSpeech(widget.content);
      if (cleaned.isEmpty) return;

      final chunks = _splitIntoChunks(cleaned);

      // Fire ALL requests up-front so the backend queues them back-to-back.
      final futures = chunks
          .map((c) => AudioService.instance
              .speak(c, voice: settings.ttsVoice, speed: settings.ttsSpeed))
          .toList();

      for (int i = 0; i < futures.length; i++) {
        if (_cancelled) break;

        final audioBytes = await futures[i];
        if (_cancelled) break;

        // Fresh player per chunk — reusing the same player for sequential
        // play() calls is unreliable across platforms (web, Android, Linux).
        _player?.dispose();
        _player = AudioPlayer();

        if (i == 0 && mounted) {
          setState(() {
            _isPlaying = true;
            _isLoading = false;
          });
        }

        final completer = Completer<void>();
        _player!.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) completer.complete();
        });

        await _player!.play(BytesSource(audioBytes));
        await completer.future;
      }

      if (mounted) {
        setState(() => _isPlaying = false);
      }
    } catch (e, stack) {
      debugPrint('[TTS] error: $e\n$stack');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPlaying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speech synthesis failed: $e')),
        );
      }
    }
  }

  Future<void> _stop() async {
    _cancelled = true;
    await _player?.stop();
    if (mounted) {
      setState(() => _isPlaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(4),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return InkWell(
      onTap: _isPlaying ? _stop : _speak,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isPlaying ? Icons.stop : Icons.volume_up,
              size: 14,
              color: _isPlaying
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(
              _isPlaying ? 'Stop' : 'Listen',
              style: TextStyle(
                fontSize: 12,
                color: _isPlaying
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
