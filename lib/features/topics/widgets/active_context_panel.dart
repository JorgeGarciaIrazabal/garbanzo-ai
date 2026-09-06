import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/topics/models/active_context.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/providers/active_context_provider.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
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
    final active = provider.context;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    TopicNode? parentNode;
    List<TopicNode> childNodes = const [];

    TopicDiscoveryProvider? discovery;
    try {
      discovery = Provider.of<TopicDiscoveryProvider?>(context);
    } catch (_) {
      discovery = null;
    }

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
                      _ContextBudgetBar(active: active),
                    if (active.topic != null)
                      _ContextTopicSection(
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
                    _ContextTree(
                      items: active.items,
                      contextSections: active.contextSections,
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
    final controller = TextEditingController();
    final l = _l10n(context);
    final source = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.addContextSource),
        content: TextField(
          key: const ValueKey('context_source_id'),
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l.contextSourceIdHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(l.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: Text(l.add),
          ),
        ],
      ),
    );
    controller.dispose();
    if (source == null || source.isEmpty || !mounted) return;
    await provider.addSource(sourceType: 'message', sourceId: source);
  }
}

class _ContextBudgetBar extends StatelessWidget {
  const _ContextBudgetBar({required this.active});
  final ActiveContext active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = _l10n(context);

    final ratio = active.tokenBudget > 0
        ? (active.tokenCount / active.tokenBudget).clamp(0.0, 1.0)
        : 0.0;
    final pct = (ratio * 100).toStringAsFixed(0);

    final meterColor = ratio > 0.9
        ? cs.error
        : ratio > 0.7
        ? Colors.amber.shade700
        : cs.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.contextTokenCount(active.tokenCount, active.tokenBudget),
                style: textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$pct% • Pack v${active.version}',
                    style: textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 10.5,
                    ),
                  ),
                  if (active.liveDeltaCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '+${active.liveDeltaCount} live',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.teal,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(meterColor),
              semanticsLabel: l10n.contextTokenUsage,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicHierarchyTree extends StatelessWidget {
  const _TopicHierarchyTree({
    required this.topic,
    this.parentNode,
    this.subtopics = const [],
  });

  final TopicNode topic;
  final TopicNode? parentNode;
  final List<TopicNode> subtopics;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                parentNode != null
                    ? Icons.folder_open_rounded
                    : Icons.hub_outlined,
                size: 15,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                parentNode?.label ?? 'Topic Graph Root',
                style: textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  subtopics.isEmpty ? '└── ' : '├── ',
                  style: TextStyle(
                    color: cs.primary.withValues(alpha: 0.7),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.stars_rounded,
                          size: 13,
                          color: cs.onPrimaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            topic.label,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelMedium?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'ACTIVE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (subtopics.isNotEmpty) ...[
            const SizedBox(height: 5),
            for (var i = 0; i < subtopics.length; i++)
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Row(
                  children: [
                    Text(
                      i == subtopics.length - 1 ? '└── ' : '├── ',
                      style: TextStyle(
                        color: cs.outline.withValues(alpha: 0.7),
                        fontFamily: 'monospace',
                      ),
                    ),
                    Icon(
                      Icons.subdirectory_arrow_right_rounded,
                      size: 12,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        subtopics[i].label,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ContextTopicSection extends StatelessWidget {
  const _ContextTopicSection({
    required this.topic,
    required this.topicPinned,
    required this.onPinToggle,
    required this.onRedirect,
    this.topicDescription,
    this.parentNode,
    this.childNodes = const [],
    this.initiallyExpanded = true,
  });

  final TopicNode topic;
  final bool topicPinned;
  final ValueChanged<bool> onPinToggle;
  final VoidCallback onRedirect;
  final String? topicDescription;
  final TopicNode? parentNode;
  final List<TopicNode> childNodes;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final resolvedDescription =
        (topicDescription != null && topicDescription!.trim().isNotEmpty)
        ? topicDescription!.trim()
        : topic.description?.trim();

    return Card(
      key: const ValueKey('context_topic_section'),
      elevation: 0,
      color: cs.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(Icons.bubble_chart_rounded, color: cs.primary, size: 20),
        title: Row(
          children: [
            Expanded(
              child: Text(
                topic.label,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                topic.origin.name.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(l10n.currentTopic),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        children: [
          if (topic.combinedTopics.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.secondary.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.merge_type_rounded, size: 16, color: cs.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'COMBINED TOPICS',
                          style: textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: cs.secondary,
                            fontSize: 9,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          topic.combinedTopics.join(', '),
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (resolvedDescription != null &&
              resolvedDescription.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.explore_outlined, size: 15, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                        'ABOUT THIS TOPIC',
                        style: textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: cs.primary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    resolvedDescription,
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurface,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          _TopicHierarchyTree(
            topic: topic,
            parentNode: parentNode,
            subtopics: childNodes,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      topicPinned
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      size: 16,
                      color: topicPinned ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                l10n.lockTopic,
                                style: textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (topicPinned
                                              ? cs.primaryContainer
                                              : cs.surfaceContainerHighest)
                                          .withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  topicPinned
                                      ? l10n.topicLocked
                                      : l10n.topicUnlocked,
                                  style: textTheme.labelSmall?.copyWith(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: topicPinned
                                        ? cs.onPrimaryContainer
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.lockTopicDescription,
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      key: const ValueKey('context_topic_pin'),
                      value: topicPinned,
                      onChanged: onPinToggle,
                    ),
                  ],
                ),
                const Divider(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Change topic focus:',
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      key: const ValueKey('context_redirect'),
                      onPressed: onRedirect,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                      label: Text(l10n.redirect),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextTree extends StatelessWidget {
  const _ContextTree({required this.items, this.contextSections = const []});
  final List<ActiveContextItem> items;
  final List<ContextSection> contextSections;
  static const _order = [
    'carryover',
    'memory',
    'message',
    'history',
    'knowledge',
    'topic_assertion',
    'attachment',
  ];

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      final infoSections = contextSections
          .where(
            (s) => s.id == 'active_context' || s.title.contains('Information'),
          )
          .toList();
      if (infoSections.isNotEmpty && infoSections.first.sentences.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final sentence in infoSections.first.sentences)
              Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 6),
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sentence,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Topic Knowledge',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          _l10n(context).noDynamicSources,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final groups = <String, List<ActiveContextItem>>{};
    for (final i in items) {
      groups.putIfAbsent(i.sourceType, () => []).add(i);
    }
    final sorted = groups.keys.toList()
      ..sort(
        (a, b) => (_order.contains(a) ? _order.indexOf(a) : 99).compareTo(
          _order.contains(b) ? _order.indexOf(b) : 99,
        ),
      );
    return Column(
      children: [
        for (final t in sorted)
          _ContextBranch(sourceType: t, items: groups[t]!),
      ],
    );
  }
}

class _ContextBranch extends StatelessWidget {
  const _ContextBranch({required this.sourceType, required this.items});
  final String sourceType;
  final List<ActiveContextItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final cs = Theme.of(context).colorScheme;
    final pinned = items
        .where((i) => i.state == ActiveContextItemState.pinned)
        .length;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: ExpansionTile(
        key: ValueKey('context_branch_$sourceType'),
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: Icon(_icon(sourceType), size: 18, color: cs.primary),
        title: Row(
          children: [
            Text(
              _label(l10n, sourceType),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                l10n.contextItemCount(items.length),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (pinned > 0) ...[
              const SizedBox(width: 4),
              Icon(Icons.push_pin, size: 11, color: cs.tertiary),
            ],
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        children: [for (final item in items) _ContextItemTile(item: item)],
      ),
    );
  }

  static IconData _icon(String t) => switch (t) {
    'carryover' => Icons.history_toggle_off_rounded,
    'memory' => Icons.lightbulb_outline_rounded,
    'message' => Icons.chat_bubble_outline_rounded,
    'history' => Icons.history_rounded,
    'knowledge' => Icons.menu_book_outlined,
    'topic_assertion' => Icons.verified_outlined,
    'attachment' => Icons.attach_file_rounded,
    _ => Icons.data_object_rounded,
  };

  static String _label(AppLocalizations l, String t) => switch (t) {
    'carryover' => l.carryover,
    'memory' => l.sourceTypeMemory,
    'message' => l.sourceTypeMessage,
    'history' => l.sourceTypeHistory,
    'knowledge' => l.sourceTypeKnowledge,
    'topic_assertion' => 'Topic Assertions',
    'attachment' => 'Attachments',
    _ => l.sourceTypeOther,
  };
}

class _ContextItemTile extends StatelessWidget {
  const _ContextItemTile({required this.item});
  final ActiveContextItem item;

  @override
  Widget build(BuildContext context) {
    final l = _l10n(context);
    final cs = Theme.of(context).colorScheme;
    final isPinned = item.state == ActiveContextItemState.pinned;

    final displayTitle = item.title ?? item.summary ?? item.highLevelSentence;
    final displaySentence = item.highLevelSentence;
    final hasCategory =
        item.categoryLabel != null && item.categoryLabel!.isNotEmpty;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isPinned
              ? cs.primary.withValues(alpha: 0.35)
              : cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: ExpansionTile(
        key: ValueKey('context_item_${item.id}'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: isPinned
            ? Icon(Icons.push_pin, size: 14, color: cs.primary)
            : null,
        title: Text(
          displayTitle,
          style: TextStyle(
            fontWeight: isPinned ? FontWeight.w600 : FontWeight.w500,
            fontSize: 13.5,
          ),
        ),
        subtitle: (item.title != null && displaySentence != item.title)
            ? Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  displaySentence,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),
              )
            : (hasCategory
                  ? Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.categoryLabel!,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : null),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 8, 10),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.whyIncluded(item.reason),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Container(
            key: ValueKey('context_item_provenance_${item.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link_rounded, size: 12, color: cs.primary),
                const SizedBox(width: 4),
                Text(
                  'Source: ${item.sourceType}${item.sourceId.isNotEmpty ? " #${item.sourceId.substring(0, item.sourceId.length > 8 ? 8 : item.sourceId.length)}" : ""}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              TextButton.icon(
                onPressed: () =>
                    context.read<ActiveContextProvider>().setItemState(
                      item.id,
                      isPinned
                          ? ActiveContextItemState.dynamic
                          : ActiveContextItemState.pinned,
                    ),
                icon: Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 15,
                ),
                label: Text(isPinned ? l.unpin : l.pin),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              TextButton.icon(
                onPressed: () => context
                    .read<ActiveContextProvider>()
                    .setItemState(item.id, ActiveContextItemState.excluded),
                icon: const Icon(Icons.remove_circle_outline, size: 15),
                label: Text(l.remove),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: cs.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
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

class _ReadinessBanner extends StatefulWidget {
  const _ReadinessBanner({required this.readiness});
  final ActiveContextReadiness readiness;

  @override
  State<_ReadinessBanner> createState() => _ReadinessBannerState();
}

class _ReadinessBannerState extends State<_ReadinessBanner>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant _ReadinessBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readiness != widget.readiness) {
      _syncController();
    }
  }

  void _syncController() {
    if (widget.readiness == ActiveContextReadiness.preparing) {
      _controller ??= AnimationController(
        vsync: this,
        duration: const Duration(seconds: 8),
      )..forward();
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readiness == ActiveContextReadiness.ready) {
      return const SizedBox.shrink();
    }
    final limited = widget.readiness == ActiveContextReadiness.limited;
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (limited) {
      return Semantics(
        liveRegion: true,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.tertiaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: cs.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.historicalContextLimited,
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

    final controller = _controller;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
        ),
        child: AnimatedBuilder(
          animation: controller ?? const AlwaysStoppedAnimation(0.0),
          builder: (context, _) {
            final val = controller?.value ?? 0.0;
            final stageText = val < 0.35
                ? 'Scanning topic assertions & evidence...'
                : val < 0.75
                ? 'Linking graph relationships & memories...'
                : 'Finalizing compiled context pack...';
            final pct = (val * 100).clamp(5, 99).toInt();

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: val > 0 ? val : null,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.preparingBestContext,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$pct% · <10s',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: val,
                    minHeight: 4,
                    backgroundColor: cs.primary.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(cs.primary),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      val < 0.35
                          ? Icons.travel_explore_rounded
                          : val < 0.75
                          ? Icons.hub_outlined
                          : Icons.inventory_2_outlined,
                      size: 12,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        stageText,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
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
