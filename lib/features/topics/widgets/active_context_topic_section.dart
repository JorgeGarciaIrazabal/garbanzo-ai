import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/topics/models/active_context.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

AppLocalizations _l10n(BuildContext c) =>
    AppLocalizations.of(c) ?? lookupAppLocalizations(const Locale('en'));

class ContextBudgetBar extends StatelessWidget {
  const ContextBudgetBar({super.key, required this.active});
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

class TopicHierarchyTree extends StatelessWidget {
  const TopicHierarchyTree({
    super.key,
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
              Expanded(
                child: Text(
                  parentNode?.label ?? _l10n(context).topicGraphRoot,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
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

class ContextTopicSection extends StatelessWidget {
  const ContextTopicSection({
    super.key,
    required this.topic,
    required this.topicPinned,
    required this.onPinToggle,
    required this.onRedirect,
    this.topicDescription,
    this.parentNode,
    this.childNodes = const [],
    this.initiallyExpanded = true,
    this.onViewArchives,
  });

  final TopicNode topic;
  final bool topicPinned;
  final ValueChanged<bool> onPinToggle;
  final VoidCallback onRedirect;
  final String? topicDescription;
  final TopicNode? parentNode;
  final List<TopicNode> childNodes;
  final bool initiallyExpanded;
  final VoidCallback? onViewArchives;

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
          TopicHierarchyTree(
            topic: topic,
            parentNode: parentNode,
            subtopics: childNodes,
          ),
          const SizedBox(height: 10),
          if (onViewArchives != null) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('context_view_archives'),
                onPressed: onViewArchives,
                icon: const Icon(Icons.history_rounded),
                label: Text(l10n.earlierSessions),
              ),
            ),
            const SizedBox(height: 10),
          ],
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
                              Expanded(
                                child: Text(
                                  l10n.lockTopic,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Container(
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.labelSmall?.copyWith(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: topicPinned
                                          ? cs.onPrimaryContainer
                                          : cs.onSurfaceVariant,
                                    ),
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
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      l10n.changeTopicFocus,
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
