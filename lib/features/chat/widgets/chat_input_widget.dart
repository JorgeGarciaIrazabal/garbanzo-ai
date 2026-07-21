import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_mode_page.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/attach_menu_button.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/attachment_preview.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/folder_chip.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/message_composer.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/pulsing_dot.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/voice_recording_helper.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_candidate.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_markdown.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_sources.dart';
import 'package:garbanzo_ai/features/mentions/widgets/mention_autocomplete.dart';
import 'package:garbanzo_ai/features/mentions/widgets/mention_text_controller.dart';
import 'package:garbanzo_ai/features/tools/providers/tool_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

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
    this.initialAttachments,
  });

  final void Function(String message, List<ChatAttachment> attachments) onSend;

  /// Called when the user presses the stop button during streaming.
  final VoidCallback? onStop;

  final bool isLoading;

  /// Pre-loaded attachments (e.g., from drag-and-drop).
  final List<ChatAttachment>? initialAttachments;

  @override
  State<ChatInputWidget> createState() => _ChatInputWidgetState();
}

class _ChatInputWidgetState extends State<ChatInputWidget> {
  // '#' tool mentions stay as styled tokens; '/' template picks replace the
  // token with the template's content, so '/' needs no token styling.
  final TextEditingController _controller = MentionTextController(
    triggers: {'#'},
  );
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
    // #tool mentions nudge the model with an explicit hint on the request.
    final tools = context.read<ToolProvider>().tools;
    final withHint = appendToolHint(
      text,
      mentionedToolNames(text, tools.map((t) => t.name)),
    );
    widget.onSend(withHint, attachments);
    setState(() => _attachments.clear());
  }

  // -- Mention sources ---------------------------------------------------------

  /// `/` suggestions: prompt templates. Picking one expands to the
  /// template's *content* (snippet-style) rather than a token, ready to
  /// edit and send.
  List<MentionCandidate> _templateCandidates() {
    final templates = context.read<SystemPromptProvider>().templates;
    final l10n = AppLocalizations.of(context)!;
    return [
      MentionCandidate(
        kind: MentionKind.agent,
        id: 'command:agent',
        label: l10n.messageAgentCommandTitle,
        sublabel: l10n.messageAgentCommandDescription,
        insertText: '/agent',
      ),
      for (final t in templates)
        if (t.content.trim().isNotEmpty)
          MentionCandidate(
            kind: MentionKind.template,
            id: t.id,
            label: t.name,
            sublabel: t.description,
            insertText: t.content.trim(),
          ),
    ];
  }

  /// `#` suggestions: available tools, inserted as `#tool_name` tokens.
  List<MentionCandidate> _toolCandidates() =>
      toolMentionCandidates(context.read<ToolProvider>().tools);

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
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
      final insertPos = selection.isValid
          ? selection.baseOffset
          : currentText.length;
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      logDebug('Transcription failed: $e');
      if (mounted) {
        // Map raw failures to actionable messages instead of dumping the
        // exception at the user.
        final raw = e.toString();
        final String message;
        if (raw.contains('SocketException') ||
            raw.contains('Connection') ||
            raw.contains('timed out')) {
          message = AppLocalizations.of(context)!.messageCouldNotReachServer;
        } else if (raw.contains('500') ||
            raw.contains('503') ||
            raw.contains('unavailable')) {
          message = AppLocalizations.of(context)!.messageSttUnavailable;
        } else {
          message = AppLocalizations.of(context)!.messageTranscriptionFailed;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() => _isTranscribing = false);
      }
    }
  }

  // -- File picking ----------------------------------------------------------

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  // -- Helpers ---------------------------------------------------------------

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  /// Desktop-only: pick a folder and attach it to the current conversation so
  /// the agent can read files within it. Guarded to desktop inside
  /// [AttachMenuButton] (the option only shows there).
  ///
  /// Also works on a brand-new chat before any conversation exists: the path
  /// is held as pending and transferred to the conversation id the moment the
  /// first send creates it.
  Future<void> _pickFolder() async {
    final chatProvider = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final conversationId = chatProvider.currentConversation?.id;
    final path = await FilePicker.getDirectoryPath();
    if (path == null || !mounted) return;
    try {
      await chatProvider.attachClientFolder(conversationId, path);
    } catch (e) {
      logDebug('Failed to attach folder: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.messageFolderAttachFailed)),
      );
    }
  }

  void _removeFolder() {
    final chatProvider = context.read<ChatProvider>();
    final id = chatProvider.currentConversation?.id;
    unawaited(chatProvider.clearClientFolder(id));
  }

  /// The composer's `above` slot: an attached-folder chip and/or the staged
  /// attachment previews. Null when there's nothing to show.
  Widget? _buildAbove(
    String? allowedFolder,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final hasFolder = allowedFolder != null;
    if (!hasFolder && _attachments.isEmpty) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasFolder)
          FolderChip(folderPath: allowedFolder, onRemove: _removeFolder),
        if (_attachments.isNotEmpty)
          AttachmentPreviewBar(
            attachments: _attachments,
            onRemove: _removeAttachment,
            colorScheme: colorScheme,
            textTheme: theme.textTheme,
          ),
      ],
    );
  }

  // -- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final chatProvider = context.watch<ChatProvider>();
    final allowedFolder = chatProvider.clientFolderFor(
      chatProvider.currentConversation?.id,
    );

    return MentionAutocomplete(
      controller: _controller,
      focusNode: _focusNode,
      sources: {'/': _templateCandidates, '#': _toolCandidates},
      child: MessageComposer(
        key: _composerKey,
        controller: _controller,
        focusNode: _focusNode,
        onSend: _handleSend,
        onStop: widget.onStop,
        isLoading: widget.isLoading,
        hasExtraContent: _attachments.isNotEmpty,
        above: _buildAbove(allowedFolder, colorScheme, theme),
        leading: AttachMenuButton(
          buttonKey: const ValueKey('attach_button'),
          enabled: !widget.isLoading,
          existingNames: () => _attachments.map((a) => a.name).toSet(),
          onAdded: (added) => setState(() => _attachments.addAll(added)),
          onPickFolder: _pickFolder,
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
                      AppLocalizations.of(
                        context,
                      )!.messageRecording(_formatDuration(_recordingDuration)),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w500,
                        fontSize: isMobile ? 12 : null,
                      ),
                    ),
                  ],
                ),
              ),
        // Dictation mic + call-style Talk Mode entry, side by side (idea 15).
        // Both give way to the send button once there's text, and to the stop
        // button while streaming — which also covers the old "disabled while
        // sending" guard on the app bar's talk button this replaces.
        idleTrailingBuilder: (_) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isTranscribing)
              SizedBox(
                width: isMobile ? 32 : 40,
                height: isMobile ? 32 : 40,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
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
            SizedBox(width: isMobile ? 2 : 4),
            IconButton.filledTonal(
              key: const ValueKey('talk_mode_button'),
              // Disabled mid-dictation so a stray tap can't open a call over
              // an in-progress recording/transcription.
              onPressed: _isRecording || _isTranscribing
                  ? null
                  : () => TalkModePage.open(
                      context,
                      chat: context.read<ChatProvider>(),
                      settings: context.read<SettingsProvider>(),
                    ),
              icon: Icon(Icons.graphic_eq, size: isMobile ? 20 : 22),
              tooltip: 'Start a voice call',
              style: IconButton.styleFrom(
                minimumSize: Size(isMobile ? 32 : 40, isMobile ? 32 : 40),
                padding: EdgeInsets.zero,
              ),
              constraints: BoxConstraints(
                minWidth: isMobile ? 32 : 40,
                minHeight: isMobile ? 32 : 40,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
