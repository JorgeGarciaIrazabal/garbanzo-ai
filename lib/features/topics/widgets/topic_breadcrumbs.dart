import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class TopicBreadcrumbs extends StatelessWidget {
  const TopicBreadcrumbs({
    super.key,
    required this.path,
    required this.onSelected,
  });

  final List<TopicNode> path;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return const SizedBox.shrink();
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('en'));
    return Center(
      child: Wrap(
        key: const ValueKey('topic_breadcrumbs'),
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        children: [
          _Crumb(
            label: l10n.allTopics,
            current: path.isEmpty,
            onTap: () => onSelected(-1),
          ),
          for (var index = 0; index < path.length; index++) ...[
            Icon(
              Icons.chevron_right_rounded,
              size: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            _Crumb(
              label: path[index].label,
              current: index == path.length - 1,
              onTap: () => onSelected(index),
            ),
          ],
        ],
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.current,
    required this.onTap,
  });

  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: current
          ? cs.surfaceContainerHighest.withValues(alpha: 0.7)
          : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: 11.5,
              fontWeight: current ? FontWeight.w700 : FontWeight.w600,
              color: current ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
