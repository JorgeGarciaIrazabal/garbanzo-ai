import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class TopicButton extends StatelessWidget {
  const TopicButton({
    super.key,
    required this.topic,
    required this.onStart,
    this.parentLabel,
    this.colorSeed,
    this.onOpenChildren,
    this.promoted = false,
    this.compact = false,
  });

  final TopicNode topic;
  final String? parentLabel;
  final String? colorSeed;
  final VoidCallback onStart;
  final VoidCallback? onOpenChildren;
  final bool promoted;
  final bool compact;

  static const _palette = <Color>[
    Color(0xff3157c8),
    Color(0xffa56210),
    Color(0xff7751b8),
    Color(0xffb44f75),
    Color(0xff1d8865),
    Color(0xff347f85),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent =
        _palette[_stableHash(colorSeed ?? topic.id) % _palette.length];
    final importance = _importance(topic.score);
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('en'));
    final subtitle = parentLabel == null ? topic.signal : null;
    final dark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(
      compact ? 12 + importance * 4 : 20 + importance * 14,
    );
    final displayTitle = shortenTopicTitle(
      topic.label,
      isMobile: compact,
      maxChars: 26,
    );
    final effectiveChildCount = topic.children.isNotEmpty
        ? topic.children.length
        : topic.childCount;
    final hasMultipleSubtopics = effectiveChildCount > 1;

    return Semantics(
      button: true,
      label: [
        topic.label,
        if (parentLabel != null) l10n.subtopicIn(parentLabel!),
        ?subtitle,
      ].join(', '),
      child: ConstrainedBox(
        key: ValueKey('topic_surface_${topic.id}'),
        constraints: BoxConstraints(
          minHeight: compact
              ? (promoted ? 42.0 + importance * 10.0 : 54.0 + importance * 18.0)
              : (promoted
                    ? 48.0 + importance * 12.0
                    : 64.0 + importance * 32.0),
          minWidth: compact ? 0 : (promoted ? 120 : 140),
        ),
        child: Material(
          color: accent.withValues(alpha: dark ? 0.14 : 0.09),
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('topic_button_${topic.id}'),
            onTap: (hasMultipleSubtopics && onOpenChildren != null)
                ? onOpenChildren
                : topic.canStart
                ? onStart
                : null,
            splashColor: accent.withValues(alpha: 0.12),
            highlightColor: accent.withValues(alpha: 0.08),
            hoverColor: accent.withValues(alpha: 0.06),
            borderRadius: radius,
            child: Tooltip(
              message: hasMultipleSubtopics
                  ? l10n.browseTopicSubtopics(topic.label)
                  : (displayTitle != topic.label ? topic.label : ''),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact
                      ? 8
                      : (promoted ? 14 : 16 + importance * 4),
                  vertical: compact
                      ? (6.0 + importance * 3.0)
                      : (promoted ? 10 + importance * 2 : 12 + importance * 8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (parentLabel != null) ...[
                      _BranchBadge(
                        key: ValueKey('subtopic_marker_${topic.id}'),
                        label: l10n.subtopicIn(parentLabel!),
                        accent: accent,
                        compact: compact,
                      ),
                      SizedBox(height: compact ? 3 : 5),
                    ],
                    Text(
                      displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Color.lerp(
                          cs.onSurface,
                          accent,
                          dark ? 0.3 : 0.5,
                        ),
                        fontSize: compact
                            ? (12.5 + importance * 2.0)
                            : (promoted
                                  ? 14 + importance * 3
                                  : 15 + importance * 7),
                        height: compact ? 1.15 : 1.08,
                        fontWeight: importance > 0.78
                            ? FontWeight.w800
                            : FontWeight.w700,
                        letterSpacing: compact ? -0.15 : -0.3,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      SizedBox(height: compact ? 2 : 4),
                      _TopicMeta(
                        icon: Icons.history_rounded,
                        text: subtitle,
                        accent: accent,
                        compact: compact,
                      ),
                    ],
                    if (hasMultipleSubtopics && parentLabel == null) ...[
                      SizedBox(height: compact ? 2 : 4),
                      _TopicMeta(
                        icon: Icons.account_tree_outlined,
                        text: l10n.subtopicCount(effectiveChildCount),
                        accent: accent,
                        compact: compact,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static double _importance(double score) =>
      score > 1 ? (score / 100).clamp(0, 1) : score.clamp(0, 1);

  static int _stableHash(String value) =>
      value.runes.fold(17, (hash, rune) => (hash * 31 + rune) & 0x7fffffff);
}

/// Shortens verbose topic titles on mobile screens for improved readability.
/// Short or single-phrase titles are preserved as-is. Delimited titles (with
/// hyphens, en-dashes, or colons) are parsed to select the most concise,
/// meaningful clause. Verbose trailing suffixes are cleanly removed.
String shortenTopicTitle(
  String title, {
  bool isMobile = false,
  int maxChars = 26,
}) {
  if (!isMobile || title.length <= maxChars) {
    return title;
  }

  // 1. If separated by dash/en-dash/em-dash or colon (e.g. "Action – Subject"),
  // pick the most specific, concise clause.
  final delimiterRegex = RegExp(r'\s+[–—\-]\s+|:\s+');
  final match = delimiterRegex.firstMatch(title);
  if (match != null) {
    final before = title.substring(0, match.start).trim();
    final after = title.substring(match.end).trim();
    if (after.isNotEmpty && after.length <= maxChars) {
      return after;
    }
    if (before.isNotEmpty && before.length <= maxChars) {
      return before;
    }
  }

  // 2. Strip common repetitive filler / verbose trailing clauses
  var result = title;
  const verboseSuffixes = [
    ' Property Search',
    ' for Home Purchase',
    ' Hardware Benchmarks',
    ' & Land Purchase',
    ' Benchmarks',
    ' Cost in Spain',
  ];

  for (final suffix in verboseSuffixes) {
    if (result.endsWith(suffix)) {
      final candidate = result
          .substring(0, result.length - suffix.length)
          .trim();
      if (candidate.isNotEmpty) {
        result = candidate;
        if (result.length <= maxChars) {
          return result;
        }
      }
    }
  }

  // 3. If still exceeding maxChars, truncate cleanly at word boundary
  final words = result.split(' ');
  final buffer = StringBuffer();
  for (final word in words) {
    if (buffer.isEmpty) {
      buffer.write(word);
    } else if (buffer.length + 1 + word.length <= maxChars) {
      buffer.write(' $word');
    } else {
      break;
    }
  }

  return buffer.isEmpty
      ? (result.length > maxChars ? result.substring(0, maxChars) : result)
      : buffer.toString();
}

class _BranchBadge extends StatelessWidget {
  const _BranchBadge({
    super.key,
    required this.label,
    required this.accent,
    this.compact = false,
  });

  final String label;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      compact ? 5 : 6,
      compact ? 2 : 3,
      compact ? 5 : 7,
      compact ? 2 : 3,
    ),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.subdirectory_arrow_right_rounded,
          size: compact ? 10 : 12,
          color: accent,
        ),
        SizedBox(width: compact ? 2 : 3),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: accent,
              fontSize: compact ? 8.5 : 9.5,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TopicMeta extends StatelessWidget {
  const _TopicMeta({
    required this.icon,
    required this.text,
    required this.accent,
    this.compact = false,
  });

  final IconData icon;
  final String text;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: compact ? 11 : 13, color: accent),
      SizedBox(width: compact ? 3 : 4),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Color.lerp(
              Theme.of(context).colorScheme.onSurfaceVariant,
              accent,
              0.38,
            ),
            fontSize: compact ? 9.5 : null,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}
