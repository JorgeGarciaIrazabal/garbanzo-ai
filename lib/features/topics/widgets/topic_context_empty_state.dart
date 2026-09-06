import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/topics/models/active_context.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/providers/active_context_provider.dart';

/// Clean, modern empty state rendered in the primary chat when a topic is active
/// and no messages have been sent in the current session epoch yet.
///
/// Surfaces the topic identity, structured context breakdown (carryover decisions,
/// pinned constraints, memories, topic knowledge graph assertions), and interactive
/// starter prompts.
class TopicContextEmptyState extends StatefulWidget {
  const TopicContextEmptyState({
    super.key,
    required this.conversationId,
    required this.topic,
    required this.onStarterSelected,
    this.onOpenContext,
  });

  final String conversationId;
  final TopicNode topic;
  final ValueChanged<String> onStarterSelected;
  final VoidCallback? onOpenContext;

  @override
  State<TopicContextEmptyState> createState() => _TopicContextEmptyStateState();
}

class _TopicContextEmptyStateState extends State<TopicContextEmptyState> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final activeContext = context.read<ActiveContextProvider>();
        if (!activeContext.loading &&
            (activeContext.context == null ||
                activeContext.context?.topic?.id != widget.topic.id)) {
          unawaited(activeContext.load(widget.conversationId, quiet: true));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final activeContext = context.watch<ActiveContextProvider>();
    final items = activeContext.context?.items ?? const <ActiveContextItem>[];
    final starters = widget.topic.starterPrompts.isNotEmpty
        ? widget.topic.starterPrompts
        : [
            'Continue with ${widget.topic.label}',
            'What should I do next about ${widget.topic.label}?',
          ];
    final topicDesc =
        activeContext.context?.topicDescription ??
        widget.topic.description ??
        activeContext.context?.topic?.description;
    final resolvedParentLabel =
        widget.topic.parentLabel ?? activeContext.context?.topic?.parentLabel;
    final contextSentences =
        activeContext.context?.contextSections
            .where(
              (s) =>
                  s.id == 'active_context' || s.title.contains('Information'),
            )
            .expand((s) => s.sentences)
            .toList() ??
        const <String>[];

    final carryover = items
        .where((it) => it.sourceType == 'carryover')
        .toList();
    final pinned = items
        .where((it) => it.state == ActiveContextItemState.pinned)
        .toList();
    final memories = items.where((it) => it.sourceType == 'memory').toList();
    final knowledge = items
        .where(
          (it) => it.sourceType != 'carryover' && it.sourceType != 'memory',
        )
        .toList();

    return Center(
      child: SingleChildScrollView(
        key: const ValueKey('topic_context_empty_state'),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Ambient Topic Icon with Aura
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: isDark ? 0.35 : 0.2),
                      cs.tertiary.withValues(alpha: isDark ? 0.25 : 0.15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: isDark ? 0.22 : 0.14),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Icon(Icons.hub_rounded, size: 32, color: cs.primary),
              ),
              const SizedBox(height: 16),

              // Topic Title
              Text(
                widget.topic.label,
                key: const ValueKey('topic_empty_state_title'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),

              // Status Pill with Glowing Dot
              _TopicStatusPill(
                status: widget.topic.contextStatus,
                parentLabel: resolvedParentLabel,
              ),
              const SizedBox(height: 28),

              // Structured Context Glassmorphic Card
              Container(
                key: const ValueKey('topic_empty_state_context_card'),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(
                    alpha: isDark ? 0.45 : 0.55,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(
                      alpha: isDark ? 0.35 : 0.5,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.18 : 0.04,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Card Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              size: 16,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'STRUCTURED ACTIVE CONTEXT',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                    color: cs.primary,
                                  ),
                                ),
                                Text(
                                  'Grounded facts & constraints active for this session',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (items.isNotEmpty || contextSentences.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer.withValues(
                                  alpha: 0.5,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: cs.primary.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Text(
                                '${items.isNotEmpty ? items.length : contextSentences.length} facts',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Topic High-Level Description (What the topic is about)
                      if (topicDesc != null && topicDesc.trim().isNotEmpty) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.35,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cs.outlineVariant.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.explore_outlined,
                                  size: 16,
                                  color: cs.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ABOUT THIS TOPIC',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.6,
                                            color: cs.primary,
                                            fontSize: 10,
                                          ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      topicDesc.trim(),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.onSurface,
                                            height: 1.4,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // What will be added to context header
                      Text(
                        'WHAT WILL BE ADDED TO CONTEXT',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: cs.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Category Summary Chips
                      if (items.isNotEmpty) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (carryover.isNotEmpty)
                              _ContextPillBadge(
                                icon: Icons.sync_alt_rounded,
                                label: '${carryover.length} carried over',
                                accentColor: Colors.amber.shade700,
                              ),
                            if (pinned.isNotEmpty)
                              _ContextPillBadge(
                                icon: Icons.push_pin_rounded,
                                label: '${pinned.length} pinned',
                                accentColor: Colors.purple.shade400,
                              ),
                            if (memories.isNotEmpty)
                              _ContextPillBadge(
                                icon: Icons.psychology_outlined,
                                label: '${memories.length} memories',
                                accentColor: Colors.blue.shade500,
                              ),
                            if (knowledge.isNotEmpty)
                              _ContextPillBadge(
                                icon: Icons.hub_outlined,
                                label: '${knowledge.length} topic facts',
                                accentColor: Colors.teal.shade500,
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ] else if (contextSentences.isNotEmpty) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ContextPillBadge(
                              icon: Icons.hub_outlined,
                              label: '${contextSentences.length} topic facts',
                              accentColor: Colors.teal.shade500,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Items List or Empty State Notice
                      if (activeContext.loading &&
                          activeContext.context == null) ...[
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            ),
                          ),
                        ),
                      ] else if (items.isNotEmpty) ...[
                        // Context Items Showcase
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final item in items.take(4))
                              _ContextItemTile(item: item),
                            if (items.length > 4)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '+ ${items.length - 4} more facts active in context',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ] else if (contextSentences.isNotEmpty) ...[
                        // Context Sentences Showcase from GraphRAG
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final sentence in contextSentences.take(4))
                              _ContextSentenceTile(sentence: sentence),
                            if (contextSentences.length > 4)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '+ ${contextSentences.length - 4} more facts active in context',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surface.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cs.outlineVariant.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline_rounded,
                                size: 18,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Clean session started. Established decisions, rules, and topic knowledge will automatically ground here as you chat.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Footer Actions
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            items.isNotEmpty
                                ? 'Grounded via GraphRAG'
                                : 'Topic Graph Engine',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                              fontSize: 11,
                            ),
                          ),
                          if (widget.onOpenContext != null)
                            TextButton.icon(
                              onPressed: widget.onOpenContext,
                              icon: const Icon(Icons.tune_rounded, size: 14),
                              label: const Text('Manage Context'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                textStyle: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Starter Prompts Section
              if (starters.isNotEmpty) ...[
                const SizedBox(height: 28),
                Row(
                  children: [
                    Icon(
                      Icons.tips_and_updates_outlined,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Suggested Starters',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < starters.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _StarterPromptCard(
                          key: ValueKey('topic_starter_chip_$i'),
                          prompt: starters[i],
                          onTap: () => widget.onStarterSelected(starters[i]),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicStatusPill extends StatelessWidget {
  const _TopicStatusPill({required this.status, this.parentLabel});

  final TopicContextStatus status;
  final String? parentLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isPreparing = status == TopicContextStatus.preparing;

    final isUuid =
        parentLabel != null &&
        parentLabel!.contains('-') &&
        parentLabel!.length >= 32;
    final displayDomain = isUuid ? null : parentLabel;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: isPreparing
                ? cs.tertiaryContainer.withValues(alpha: 0.5)
                : cs.secondaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPreparing
                  ? cs.tertiary.withValues(alpha: 0.3)
                  : cs.secondary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPreparing)
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.4, end: 1.0),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeInOut,
                  builder: (context, anim, child) => Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.tertiary.withValues(alpha: anim),
                      boxShadow: [
                        BoxShadow(
                          color: cs.tertiary.withValues(alpha: anim * 0.6),
                          blurRadius: 4 + anim * 4,
                          spreadRadius: anim,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.shade600,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.shade600.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 7),
              Text(
                isPreparing ? 'Preparing context...' : 'Context ready',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isPreparing
                      ? cs.onTertiaryContainer
                      : cs.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
        if (displayDomain != null && displayDomain.isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Domain: $displayDomain',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ContextPillBadge extends StatelessWidget {
  const _ContextPillBadge({
    required this.icon,
    required this.label,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accentColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextItemTile extends StatelessWidget {
  const _ContextItemTile({required this.item});

  final ActiveContextItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isCarryover = item.sourceType == 'carryover';
    final isPinned = item.state == ActiveContextItemState.pinned;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCarryover
              ? Colors.amber.withValues(alpha: 0.3)
              : cs.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              isCarryover
                  ? Icons.sync_alt_rounded
                  : (isPinned
                        ? Icons.push_pin_rounded
                        : Icons.auto_awesome_rounded),
              size: 15,
              color: isCarryover
                  ? Colors.amber.shade700
                  : (isPinned ? Colors.purple.shade400 : cs.primary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.highLevelSentence,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (isCarryover
                                ? Colors.amber
                                : (isPinned ? Colors.purple : cs.primary))
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.categoryLabel ??
                        (isCarryover
                            ? 'Carried Over Context'
                            : (isPinned ? 'Pinned Fact' : 'Active Context')),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: isCarryover
                          ? Colors.amber.shade800
                          : (isPinned ? Colors.purple.shade700 : cs.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextSentenceTile extends StatelessWidget {
  const _ContextSentenceTile({required this.sentence});

  final String sentence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: 15,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sentence,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Topic Knowledge',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StarterPromptCard extends StatelessWidget {
  const _StarterPromptCard({
    super.key,
    required this.prompt,
    required this.onTap,
  });

  final String prompt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(
              alpha: isDark ? 0.35 : 0.45,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 15, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  prompt,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
