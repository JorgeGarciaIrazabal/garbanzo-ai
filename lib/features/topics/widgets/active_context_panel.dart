import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/topics/models/active_context.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/providers/active_context_provider.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/features/topics/widgets/active_context_topic_section.dart';
import 'package:garbanzo_ai/features/topics/widgets/active_context_tree.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_archives_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

AppLocalizations _l10n(BuildContext c) =>
    AppLocalizations.of(c) ?? lookupAppLocalizations(const Locale('en'));

class ActiveContextPanel extends StatefulWidget {
  const ActiveContextPanel({
    super.key,
    required this.conversationId,
    required this.onRedirect,
    this.onClose,
  });
  final String conversationId;
  final VoidCallback onRedirect;
  final VoidCallback? onClose;

  static Future<void> showSheet(
    BuildContext context, {
    required String conversationId,
    required VoidCallback onRedirect,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sc) => FractionallySizedBox(
      heightFactor: 0.92,
      child: ActiveContextPanel(
        conversationId: conversationId,
        onRedirect: () {
          Navigator.of(sc).pop();
          onRedirect();
        },
        onClose: () => Navigator.of(sc).pop(),
      ),
    ),
  );

  @override
  State<ActiveContextPanel> createState() => _ActiveContextPanelState();
}

class _ActiveContextPanelState extends State<ActiveContextPanel> {
  @override
  void didUpdateWidget(covariant ActiveContextPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId == widget.conversationId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          context.read<ActiveContextProvider>().load(widget.conversationId),
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          context.read<ActiveContextProvider>().load(widget.conversationId),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ActiveContextProvider>();
    final l10n = _l10n(context);
    final active = provider.context?.conversationId == widget.conversationId
        ? provider.context
        : null;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    TopicNode? parentNode;
    List<TopicNode> childNodes = const [];

    final discovery = context.watch<TopicDiscoveryProvider?>();

    final activeTopic = active?.topic;
    if (activeTopic != null && discovery != null) {
      final activeId = activeTopic.id;
      final foundNode = _findNodeRecursive(discovery.topics, activeId);
      final foundParent = activeTopic.parentId != null
          ? _findNodeRecursive(discovery.topics, activeTopic.parentId!)
          : _findParentRecursive(discovery.topics, activeId);
      parentNode = foundParent;
      childNodes = (foundNode != null && foundNode.children.isNotEmpty)
          ? foundNode.children
          : activeTopic.children;
    } else if (activeTopic != null) {
      childNodes = activeTopic.children;
    }

    return Semantics(
      container: true,
      label: l10n.activeContext,
      child: Material(
        key: const ValueKey('active_context_panel'),
        color: cs.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.activeContext,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (active != null)
                          Text(
                            'Active working set • Pack v${active.version}',
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.onClose != null)
                    IconButton(
                      tooltip: l10n.closeActiveContext,
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (provider.loading && active == null)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (active == null)
              Expanded(
                child: _ContextUnavailable(
                  message: provider.error == null
                      ? l10n.noActiveContext
                      : _localizedError(context, provider.error!),
                  onRetry: () => provider.load(widget.conversationId),
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _ReadinessBanner(readiness: active.readiness),
                    if (active.tokenBudget > 0)
                      ContextBudgetBar(active: active),
                    if (active.topic != null)
                      ContextTopicSection(
                        topic: active.topic!,
                        topicDescription:
                            active.topicDescription ??
                            active.topic?.description,
                        topicPinned: active.topicPinned,
                        parentNode: parentNode,
                        childNodes: childNodes,
                        initiallyExpanded:
                            active.pinnedItems.isEmpty &&
                            active.dynamicItems.isEmpty,
                        onPinToggle: (val) => provider.setTopicPinned(val),
                        onRedirect: widget.onRedirect,
                        onViewArchives: discovery == null
                            ? null
                            : () => _showArchives(discovery, active.topic!.id),
                      ),
                    if (active.summary.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _SectionTitle(l10n.nextTurnPreview),
                      Card(
                        elevation: 0,
                        color: cs.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.lightbulb_outline_rounded,
                                size: 18,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  active.summary,
                                  style: textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _SectionTitle(l10n.contextIncluded),
                    ContextTree(
                      items: active.items,
                      contextSections: active.contextSections,
                      onOpenSource: _canOpenConversationSource(context)
                          ? _openSourceConversation
                          : null,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      key: const ValueKey('context_add_source'),
                      onPressed: () => _showAddSource(context),
                      icon: const Icon(Icons.add_link),
                      label: Text(l10n.addSource),
                    ),
                    if (provider.error != null) ...[
                      const SizedBox(height: 12),
                      Text(provider.error!, style: TextStyle(color: cs.error)),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  TopicNode? _findNodeRecursive(List<TopicNode> nodes, String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
      final found = _findNodeRecursive(node.children, id);
      if (found != null) return found;
    }
    return null;
  }

  TopicNode? _findParentRecursive(List<TopicNode> nodes, String targetId) {
    for (final node in nodes) {
      for (final child in node.children) {
        if (child.id == targetId) return node;
      }
      final found = _findParentRecursive(node.children, targetId);
      if (found != null) return found;
    }
    return null;
  }

  Future<void> _showAddSource(BuildContext context) async {
    final provider = context.read<ActiveContextProvider>();
    final l = _l10n(context);
    final chat = context.read<ChatProvider?>();
    final messages = chat?.messages
        .where(
          (message) =>
              (message.isUser || message.isAssistant) &&
              message.content.trim().isNotEmpty,
        )
        .toList()
        .reversed
        .take(30)
        .toList(growable: false);
    final source = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.selectContextSource),
        content: SizedBox(
          width: 520,
          child: messages == null || messages.isEmpty
              ? Text(l.noContextSourcesAvailable)
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: messages.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final message = messages[index];
                    final excerpt = message.content.trim().replaceAll(
                      RegExp(r'\s+'),
                      ' ',
                    );
                    return ListTile(
                      key: ValueKey('context_source_${message.id}'),
                      dense: true,
                      leading: Icon(
                        message.isUser
                            ? Icons.person_outline
                            : Icons.auto_awesome_outlined,
                      ),
                      title: Text(
                        excerpt,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        MaterialLocalizations.of(
                          c,
                        ).formatMediumDate(message.createdAt.toLocal()),
                      ),
                      onTap: () => Navigator.pop(c, message.id),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(l.cancel)),
        ],
      ),
    );
    if (source == null || source.isEmpty || !mounted) return;
    await provider.addSource(sourceType: 'message', sourceId: source);
  }

  Future<void> _showArchives(
    TopicDiscoveryProvider discovery,
    String topicId,
  ) async {
    await discovery.loadArchives(topicId);
    if (!mounted) return;
    final conversationId = await showDialog<String>(
      context: context,
      builder: (_) => TopicArchivesDialog(topicId: topicId),
    );
    if (!mounted || conversationId == null) return;
    final chat = context.read<ChatProvider>();
    await chat.loadConversation(conversationId);
    if (!mounted || chat.currentConversation?.id != conversationId) return;
    discovery.setSelectedTopic(chat.currentConversation?.activeTopic);
    await chat.refreshConversations();
    if (!mounted) return;
    widget.onClose?.call();
  }

  bool _canOpenConversationSource(BuildContext context) =>
      context.read<ChatProvider?>() != null;

  Future<void> _openSourceConversation(String conversationId) async {
    final chat = context.read<ChatProvider?>();
    if (chat == null) return;
    await chat.loadConversation(conversationId);
    if (mounted) widget.onClose?.call();
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _ReadinessBanner extends StatelessWidget {
  const _ReadinessBanner({required this.readiness});
  final ActiveContextReadiness readiness;

  @override
  Widget build(BuildContext context) {
    if (readiness == ActiveContextReadiness.ready) {
      return const SizedBox.shrink();
    }
    final limited = readiness == ActiveContextReadiness.limited;
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: limited
              ? cs.tertiaryContainer.withValues(alpha: 0.5)
              : cs.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              limited ? Icons.info_outline : Icons.sync,
              size: 18,
              color: limited ? cs.tertiary : cs.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                limited
                    ? l10n.historicalContextLimited
                    : l10n.contextUpdatingInBackground,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextUnavailable extends StatelessWidget {
  const _ContextUnavailable({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.layers_outlined, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: onRetry, child: Text(_l10n(context).tryAgain)),
        ],
      ),
    ),
  );
}

String _localizedError(BuildContext c, String e) => switch (e) {
  'Active context is temporarily unavailable' => _l10n(
    c,
  ).activeContextUnavailable,
  'Could not update this context source' => _l10n(c).contextSourceUpdateFailed,
  'Could not add this context source' => _l10n(c).contextSourceAddFailed,
  'Could not update topic pin' => _l10n(c).topicPinUpdateFailed,
  _ => e,
};
