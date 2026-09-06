import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/style_provider.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/services/shared_content_service.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_mode_page.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/attach_menu_button.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/attachment_preview.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/folder_chip.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/file_picker_helper.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/message_composer.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/pulsing_dot.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/voice_recording_helper.dart';
import 'package:garbanzo_ai/features/chat/widgets/style_picker.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_candidate.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_markdown.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_sources.dart';
import 'package:garbanzo_ai/features/mentions/widgets/mention_autocomplete.dart';
import 'package:garbanzo_ai/features/mentions/widgets/mention_text_controller.dart';
import 'package:garbanzo_ai/features/tools/providers/tool_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class ChatInputWidget extends StatefulWidget {
  const ChatInputWidget({
    super.key,
    required this.onSend,
    this.onStop,
    this.isLoading = false,
    this.initialAttachments,
    this.isPrimary = false,
    this.onNewTopic,
    this.onOpenContext,
  });

  final void Function(String message, List<ChatAttachment> attachments) onSend;
  final VoidCallback? onStop;
  final bool isLoading;
  final List<ChatAttachment>? initialAttachments;
  final bool isPrimary;
  final VoidCallback? onNewTopic;
  final VoidCallback? onOpenContext;

  @override
  State<ChatInputWidget> createState() => _ChatInputWidgetState();
}

class _ChatInputWidgetState extends State<ChatInputWidget> {
  final TextEditingController _controller = MentionTextController(
    triggers: {'#'},
  );
  final FocusNode _focusNode = FocusNode();
  final GlobalKey<MessageComposerState> _composerKey = GlobalKey();
  final List<ChatAttachment> _attachments = [];
  StreamSubscription<SharedContent>? _sharedContentSub;

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
    _sharedContentSub = SharedContentService.instance.incoming.listen(
      (_) => _consumeSharedContent(),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _consumeSharedContent(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _recordingTimer?.cancel();
    _sharedContentSub?.cancel();
    _voiceHelper.dispose();
    super.dispose();
  }

  void _snack(String msg, {Color? bg}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        behavior: bg != null ? SnackBarBehavior.floating : null,
      ),
    );
  }

  void _handleSend(String text) {
    final attachments = List<ChatAttachment>.from(_attachments);
    final tools = context.read<ToolProvider>().tools;
    widget.onSend(
      appendToolHint(text, mentionedToolNames(text, tools.map((t) => t.name))),
      attachments,
    );
    setState(() => _attachments.clear());
  }

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

  List<MentionCandidate> _toolCandidates() =>
      toolMentionCandidates(context.read<ToolProvider>().tools);

  Future<void> _toggleRecording() async =>
      _isRecording ? _stopRecording() : _startRecording();

  Future<void> _startRecording() async {
    try {
      await _voiceHelper.startRecording();
    } on VoiceRecordingException catch (e) {
      _snack(e.message);
      return;
    }
    setState(() {
      _isRecording = true;
      _recordingDuration = 0;
    });
    _recordingTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _recordingDuration++),
    );
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
        _snack(
          'No speech detected. Check that your microphone is set as the default input device.',
        );
        return;
      }
      final cur = _controller.text;
      final sel = _controller.selection;
      final pos = sel.isValid ? sel.baseOffset : cur.length;
      final prefix = pos > 0 && cur[pos - 1] != ' ' ? ' ' : '';
      final newText = cur.replaceRange(pos, pos, '$prefix${result.transcript}');
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(
        offset: pos + prefix.length + result.transcript.length,
      );
      final settings = context.read<SettingsProvider>();
      if (settings.autoSubmitStt && result.transcript.trim().isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) _composerKey.currentState?.submit();
      }
    } on VoiceRecordingException catch (e) {
      _snack(e.message);
    } catch (e) {
      logDebug('Transcription failed: $e');
      if (!mounted) return;
      final raw = e.toString();
      final l10n = AppLocalizations.of(context)!;
      final msg =
          raw.contains('SocketException') ||
              raw.contains('Connection') ||
              raw.contains('timed out')
          ? l10n.messageCouldNotReachServer
          : raw.contains('500') ||
                raw.contains('503') ||
                raw.contains('unavailable')
          ? l10n.messageSttUnavailable
          : l10n.messageTranscriptionFailed;
      _snack(msg);
    } finally {
      if (mounted) setState(() => _isTranscribing = false);
    }
  }

  Future<void> _consumeSharedContent() async {
    if (!mounted) return;
    final batches = SharedContentService.instance.takePending();
    if (batches.isEmpty) return;
    final result = await FilePickerHelper.validate(
      files: [
        for (final b in batches)
          for (final f in b.files) (name: f.name, bytes: f.bytes),
      ],
      existingNames: _attachments.map((a) => a.name).toSet(),
    );
    if (!mounted) return;
    final sharedText = batches
        .map((b) => b.text?.trim())
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .join('\n');
    setState(() {
      _attachments.addAll(result.added);
      if (sharedText.isNotEmpty) {
        final cur = _controller.text.trimRight();
        _controller.text = cur.isEmpty ? sharedText : '$cur\n$sharedText';
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      }
    });
    for (final e in result.validationErrors) {
      _snack(e);
    }
    if (result.rejected.isNotEmpty) {
      _snack(
        AppLocalizations.of(
          context,
        )!.messageFilesTooLarge(result.rejected.join('\n')),
        bg: Theme.of(context).colorScheme.error,
      );
    }
    _focusNode.requestFocus();
  }

  void _removeAttachment(int index) =>
      setState(() => _attachments.removeAt(index));

  String _formatDuration(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _pickFolder() async {
    final chatProvider = context.read<ChatProvider>();
    final l10n = AppLocalizations.of(context)!;
    final conversationId = chatProvider.currentConversation?.id;
    final path = await FilePicker.getDirectoryPath();
    if (path == null || !mounted) return;
    try {
      await chatProvider.attachClientFolder(conversationId, path);
    } catch (e) {
      logDebug('Failed to attach folder: $e');
      _snack(l10n.messageFolderAttachFailed);
    }
  }

  void _removeFolder() => unawaited(
    context.read<ChatProvider>().clearClientFolder(
      context.read<ChatProvider>().currentConversation?.id,
    ),
  );

  Future<void> _cycleThinkingLevel() async {
    final chat = context.read<ChatProvider>();
    final models = context.read<ModelProvider>();
    final styles = context.read<StyleProvider>();
    final modelId = chat.currentConversation?.model ?? models.selectedModelId;
    final model = models.availableModels
        .where((c) => c.id == modelId)
        .firstOrNull;
    final supported = model?.supportedThinkingLevels ?? const <ThinkingLevel>[];
    if (supported.length < 2) return;
    final current =
        chat.currentConversation?.thinkingLevel ?? styles.pendingThinkingLevel;
    final next =
        supported[(supported.indexOf(current ?? supported.last) + 1) %
            supported.length];
    styles.setPendingThinkingLevel(next);
    if (chat.currentConversation != null) {
      await chat.updateConversation(
        thinkingLevel: next,
        setThinkingLevel: true,
      );
    }
  }

  Widget? _buildAbove(String? allowedFolder, ColorScheme cs, ThemeData theme) {
    if (allowedFolder == null && _attachments.isEmpty) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allowedFolder != null)
          FolderChip(folderPath: allowedFolder, onRemove: _removeFolder),
        if (_attachments.isNotEmpty)
          AttachmentPreviewBar(
            attachments: _attachments,
            onRemove: _removeAttachment,
            colorScheme: cs,
            textTheme: theme.textTheme,
          ),
      ],
    );
  }

  // Toolbar helpers extracted for clarity and line reduction
  Widget _newTopicButton(bool isMobile, ColorScheme cs, AppLocalizations l10n) {
    const key = ValueKey('new_topic_button');
    return isMobile
        ? IconButton(
            key: key,
            onPressed: widget.onNewTopic,
            tooltip: l10n.newTopic,
            icon: const Icon(Icons.post_add_rounded),
            style: IconButton.styleFrom(
              foregroundColor: cs.primary,
              visualDensity: VisualDensity.compact,
            ),
          )
        : TextButton.icon(
            key: key,
            onPressed: widget.onNewTopic,
            icon: const Icon(Icons.post_add_rounded, size: 18),
            label: Text(l10n.newTopic),
          );
  }

  Widget _thinkingChip(
    bool isMobile,
    ColorScheme cs,
    ThinkingLevel? effort,
    AppLocalizations l10n,
  ) => ActionChip(
    key: const ValueKey('thinking_effort_chip'),
    avatar: Icon(Icons.psychology_outlined, size: isMobile ? 15 : 17),
    label: Text(effort?.label ?? l10n.thinking),
    tooltip: l10n.cycleThinkingEffort,
    onPressed: widget.isLoading ? null : _cycleThinkingLevel,
    visualDensity: isMobile
        ? const VisualDensity(horizontal: -3, vertical: -3)
        : VisualDensity.compact,
    side: BorderSide.none,
    backgroundColor: cs.tertiaryContainer.withValues(alpha: 0.6),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chatProvider = context.watch<ChatProvider>();
    final allowedFolder = chatProvider.clientFolderFor(
      chatProvider.currentConversation?.id,
    );
    final modelProvider = context.watch<ModelProvider>();
    final styleProvider = context.watch<StyleProvider>();
    final l10n = AppLocalizations.of(context)!;
    final currentModelId =
        chatProvider.currentConversation?.model ??
        modelProvider.selectedModelId;
    final currentModel = modelProvider.availableModels
        .where((m) => m.id == currentModelId)
        .firstOrNull;
    final effort =
        chatProvider.currentConversation?.thinkingLevel ??
        styleProvider.pendingThinkingLevel;
    final supportedEffort =
        currentModel?.supportedThinkingLevels ?? const <ThinkingLevel>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 620;
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
            above: _buildAbove(allowedFolder, cs, theme),
            bottomToolbar: _buildToolbar(
              isMobile,
              cs,
              l10n,
              effort,
              supportedEffort,
            ),
            leading: AttachMenuButton(
              buttonKey: const ValueKey('attach_button'),
              enabled: !widget.isLoading,
              existingNames: () => _attachments.map((a) => a.name).toSet(),
              onAdded: (added) => setState(() => _attachments.addAll(added)),
              onPickFolder: _pickFolder,
            ),
            overlay: _isRecording
                ? _recordingOverlay(isMobile, cs, theme, l10n)
                : null,
            idleTrailingBuilder: (_) => _idleTrailing(isMobile, cs),
          ),
        );
      },
    );
  }

  Widget _buildToolbar(
    bool isMobile,
    ColorScheme cs,
    AppLocalizations l10n,
    ThinkingLevel? effort,
    List<ThinkingLevel> supported,
  ) => Row(
    children: [
      if (widget.onNewTopic != null) _newTopicButton(isMobile, cs, l10n),
      if (widget.onNewTopic != null) SizedBox(width: isMobile ? 2 : 6),
      StylePickerButton(compact: isMobile),
      if (supported.length > 1) ...[
        SizedBox(width: isMobile ? 2 : 6),
        _thinkingChip(isMobile, cs, effort, l10n),
      ],
      const Spacer(),
      if (widget.isPrimary)
        IconButton(
          key: const ValueKey('active_context_button'),
          onPressed: widget.onOpenContext,
          tooltip: l10n.activeContext,
          icon: const Icon(Icons.layers_outlined),
          visualDensity: VisualDensity.compact,
        ),
    ],
  );

  Widget _recordingOverlay(
    bool isMobile,
    ColorScheme cs,
    ThemeData theme,
    AppLocalizations l10n,
  ) => Container(
    decoration: BoxDecoration(
      color: cs.errorContainer.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
      border: Border.all(color: cs.error.withValues(alpha: 0.5)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        PulsingDot(color: cs.error),
        const SizedBox(width: 6),
        Text(
          l10n.messageRecording(_formatDuration(_recordingDuration)),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onErrorContainer,
            fontWeight: FontWeight.w500,
            fontSize: isMobile ? 12 : null,
          ),
        ),
      ],
    ),
  );

  Widget _idleTrailing(bool isMobile, ColorScheme cs) {
    const sz = 32.0;
    final s = isMobile ? sz : 40.0;
    final c = BoxConstraints(minWidth: s, minHeight: s);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isTranscribing)
          SizedBox(
            width: s,
            height: s,
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
              foregroundColor: _isRecording ? cs.error : cs.onSurfaceVariant,
              minimumSize: Size(s, s),
              padding: EdgeInsets.zero,
            ),
            constraints: c,
          ),
        SizedBox(width: isMobile ? 2 : 4),
        IconButton.filledTonal(
          key: const ValueKey('talk_mode_button'),
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
            minimumSize: Size(s, s),
            padding: EdgeInsets.zero,
          ),
          constraints: c,
        ),
      ],
    );
  }
}
