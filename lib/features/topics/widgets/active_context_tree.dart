import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/topics/models/active_context.dart';
import 'package:garbanzo_ai/features/topics/providers/active_context_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

AppLocalizations _l10n(BuildContext c) =>
    AppLocalizations.of(c) ?? lookupAppLocalizations(const Locale('en'));

class ContextTree extends StatelessWidget {
  const ContextTree({
    super.key,
    required this.items,
    this.contextSections = const [],
    this.onOpenSource,
  });
  final List<ActiveContextItem> items;
  final List<ContextSection> contextSections;
  final Future<void> Function(String conversationId)? onOpenSource;
  static const _order = [
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
          ContextBranch(
            sourceType: t,
            items: groups[t]!,
            onOpenSource: onOpenSource,
          ),
      ],
    );
  }
}

class ContextBranch extends StatelessWidget {
  const ContextBranch({
    super.key,
    required this.sourceType,
    required this.items,
    this.onOpenSource,
  });
  final String sourceType;
  final List<ActiveContextItem> items;
  final Future<void> Function(String conversationId)? onOpenSource;

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
              labelFor(l10n, sourceType),
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
        children: [
          for (final item in items)
            ContextItemTile(item: item, onOpenSource: onOpenSource),
        ],
      ),
    );
  }

  static IconData _icon(String t) => switch (t) {
    'memory' => Icons.lightbulb_outline_rounded,
    'message' => Icons.chat_bubble_outline_rounded,
    'history' => Icons.history_rounded,
    'knowledge' => Icons.menu_book_outlined,
    'topic_assertion' => Icons.verified_outlined,
    'attachment' => Icons.attach_file_rounded,
    _ => Icons.data_object_rounded,
  };

  static String labelFor(AppLocalizations l, String t) => switch (t) {
    'memory' => l.sourceTypeMemory,
    'message' => l.sourceTypeMessage,
    'history' => l.sourceTypeHistory,
    'knowledge' => l.sourceTypeKnowledge,
    'topic_assertion' => 'Topic Assertions',
    'attachment' => 'Attachments',
    _ => l.sourceTypeOther,
  };
}

class ContextItemTile extends StatelessWidget {
  const ContextItemTile({super.key, required this.item, this.onOpenSource});
  final ActiveContextItem item;
  final Future<void> Function(String conversationId)? onOpenSource;

  @override
  Widget build(BuildContext context) {
    final l = _l10n(context);
    final cs = Theme.of(context).colorScheme;
    final isPinned = item.state == ActiveContextItemState.pinned;

    final displayTitle = item.title ?? item.summary ?? item.highLevelSentence;
    final displaySentence = item.highLevelSentence;
    final hasCategory =
        item.categoryLabel != null && item.categoryLabel!.isNotEmpty;
    final sourceDate = item.sourceCreatedAt == null
        ? null
        : MaterialLocalizations.of(
            context,
          ).formatMediumDate(item.sourceCreatedAt!.toLocal());
    final sourceName = item.sourceLabel?.trim().isNotEmpty == true
        ? item.sourceLabel!
        : ContextBranch.labelFor(l, item.sourceType);

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
          if (item.sourceExcerpt?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            SelectionArea(
              child: Text(
                '“${item.sourceExcerpt}”',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
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
                  sourceDate == null
                      ? l.contextSourceName(sourceName)
                      : l.contextSourceNameAndDate(sourceName, sourceDate),
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
              if (item.sourceConversationId != null && onOpenSource != null)
                TextButton.icon(
                  onPressed: () => onOpenSource!(item.sourceConversationId!),
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: Text(l.openSource),
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
