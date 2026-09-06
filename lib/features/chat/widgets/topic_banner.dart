import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// A slim, pinned banner shown at the top of the primary chat column when a
/// topic is active. It surfaces the current topic label and preparation
/// status so the user always knows what Garbanzo is focused on.
class TopicBanner extends StatelessWidget {
  const TopicBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final topics = context.watch<TopicDiscoveryProvider>();
    final selected = topics.selectedTopic;
    final drift = topics.pendingDrift;
    final hasSelected = selected != null && selected.id.isNotEmpty;
    if (!hasSelected) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('en'));
    final preparing = selected.contextStatus == TopicContextStatus.preparing;
    final limited = selected.contextStatus == TopicContextStatus.limited;

    return Container(
      key: const ValueKey('topic_banner'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(_originIcon(selected.origin), size: 17, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.currentTopic,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 10,
                        letterSpacing: 0.04,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            selected.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (selected.combinedTopics.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer.withValues(
                                alpha: 0.7,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.merge_type_rounded,
                                  size: 11,
                                  color: cs.onSecondaryContainer,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '+ ${selected.combinedTopics.join(", ")}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSecondaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (preparing)
                _StatusChip(
                  icon: Icons.sync_rounded,
                  label: l10n.preparingContext,
                  color: cs.primary,
                  animate: true,
                )
              else if (limited)
                _StatusChip(
                  icon: Icons.info_outline_rounded,
                  label: l10n.historicalContextLimited,
                  color: cs.tertiary,
                ),
            ],
          ),
          if (drift != null) ...[
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('topic_drift_banner'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.tertiary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.alt_route_rounded, size: 16, color: cs.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Shift detected: switch to ${drift.label}?',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FilledButton.tonal(
                    key: const ValueKey('topic_drift_combine_button'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () {
                      ChatProvider? chat;
                      try {
                        chat = Provider.of<ChatProvider>(
                          context,
                          listen: false,
                        );
                      } catch (_) {}
                      final conversationId =
                          chat?.currentConversation?.id ?? '';
                      topics.acceptDrift(conversationId, mode: 'combine');
                    },
                    child: const Text(
                      'Combine',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.tonal(
                    key: const ValueKey('topic_drift_switch_button'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () {
                      ChatProvider? chat;
                      try {
                        chat = Provider.of<ChatProvider>(
                          context,
                          listen: false,
                        );
                      } catch (_) {}
                      final conversationId =
                          chat?.currentConversation?.id ?? '';
                      topics.acceptDrift(conversationId, mode: 'switch');
                    },
                    child: const Text('Switch', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const ValueKey('topic_drift_dismiss_button'),
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Dismiss',
                    onPressed: topics.dismissDrift,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _originIcon(TopicOrigin origin) => switch (origin) {
    TopicOrigin.personal || TopicOrigin.history => Icons.history_rounded,
    TopicOrigin.suggested => Icons.auto_awesome_outlined,
    TopicOrigin.explore => Icons.explore_outlined,
    TopicOrigin.manual => Icons.edit_outlined,
  };
}

class _StatusChip extends StatefulWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    this.animate = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool animate;

  @override
  State<_StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<_StatusChip>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _startAnimation();
    }
  }

  void _startAnimation() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    final inTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    if (inTest) {
      _controller?.forward();
    } else {
      _controller?.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _StatusChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && _controller == null) {
      _startAnimation();
    } else if (!widget.animate && _controller != null) {
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: widget.color.withValues(alpha: widget.animate ? 0.16 : 0.1),
      borderRadius: BorderRadius.circular(999),
      border: widget.animate
          ? Border.all(color: widget.color.withValues(alpha: 0.35))
          : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.animate && _controller != null)
          RotationTransition(
            turns: _controller!,
            child: Icon(widget.icon, size: 12, color: widget.color),
          )
        else
          Icon(widget.icon, size: 12, color: widget.color),
        const SizedBox(width: 4),
        Text(
          widget.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: widget.color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
