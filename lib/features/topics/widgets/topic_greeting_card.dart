import 'package:flutter/material.dart';

class TopicGreetingData {
  const TopicGreetingData({
    required this.topicLabel,
    this.topicDescription,
    this.sentences = const [],
    this.fallbackDescription,
    this.prompt,
  });

  final String topicLabel;
  final String? topicDescription;
  final List<String> sentences;
  final String? fallbackDescription;
  final String? prompt;

  static TopicGreetingData? tryParse(String content) {
    final trimmed = content.trim();
    if (!trimmed.startsWith('### Topic: **')) return null;

    final headerMatch = RegExp(
      r'^### Topic:\s*\*\*(.*?)\*\*',
    ).firstMatch(trimmed);
    if (headerMatch == null) return null;
    final topicLabel = headerMatch.group(1)?.trim() ?? '';
    if (topicLabel.isEmpty) return null;

    final lines = trimmed.split('\n');
    String? description;
    final sentences = <String>[];
    String? fallbackDesc;
    String? prompt;

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (description == null &&
          line.startsWith('*') &&
          line.endsWith('*') &&
          !line.startsWith('**')) {
        description = line.substring(1, line.length - 1).trim();
        continue;
      }

      if (line.startsWith('• ') || line.startsWith('- ')) {
        sentences.add(line.substring(2).trim());
        continue;
      }

      if (line.startsWith('**Context included in this thread:**')) {
        continue;
      }

      if (line.startsWith('How can I help you with')) {
        prompt = line.replaceAll('*', '').trim();
        continue;
      }

      if (line.startsWith('This thread is focused on')) {
        fallbackDesc = line.replaceAll('*', '').trim();
        continue;
      }
    }

    return TopicGreetingData(
      topicLabel: topicLabel,
      topicDescription: description,
      sentences: sentences,
      fallbackDescription: fallbackDesc,
      prompt: prompt ?? 'How can I help you with $topicLabel today?',
    );
  }
}

/// Unified, rich topic context card rendered inside a thread's message history
/// representing the initial topic greeting and active context briefing.
class TopicGreetingCard extends StatelessWidget {
  const TopicGreetingCard({super.key, required this.data, this.onOpenContext});

  final TopicGreetingData data;
  final VoidCallback? onOpenContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Container(
            key: const ValueKey('topic_greeting_card'),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(
                alpha: isDark ? 0.4 : 0.5,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.primary.withValues(alpha: isDark ? 0.3 : 0.22),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: isDark ? 0.08 : 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header row with Icon, Label, and Status Chip
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
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
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                      ),
                      child: Icon(
                        Icons.hub_rounded,
                        size: 18,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'THREAD CONTEXT',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            data.topicLabel,
                            key: const ValueKey('topic_greeting_title'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(
                          alpha: isDark ? 0.45 : 0.6,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Active',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Description
                if (data.topicDescription != null &&
                    data.topicDescription!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    data.topicDescription!,
                    key: const ValueKey('topic_greeting_description'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],

                // Structured context sentences
                if (data.sentences.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.22)
                          : cs.surfaceContainerLow.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(
                          alpha: isDark ? 0.3 : 0.4,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 13,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Context included in this thread',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...data.sentences.map(
                          (sentence) => Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 5,
                                    right: 8,
                                  ),
                                  child: Container(
                                    width: 4.5,
                                    height: 4.5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: cs.primary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    sentence,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      height: 1.35,
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
                ] else if (data.fallbackDescription != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    data.fallbackDescription!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],

                // Footer Prompt & Action
                if (data.prompt != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data.prompt!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      if (onOpenContext != null)
                        TextButton.icon(
                          onPressed: onOpenContext,
                          icon: Icon(
                            Icons.auto_awesome_outlined,
                            size: 14,
                            color: cs.primary,
                          ),
                          label: Text(
                            'View Details',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
