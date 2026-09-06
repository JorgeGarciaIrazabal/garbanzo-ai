import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_button.dart';

class TopicField extends StatelessWidget {
  const TopicField({
    super.key,
    required this.topics,
    required this.onStart,
    required this.onOpenChildren,
    this.parentLabel,
    this.promotedCount = 4,
  });

  final List<TopicNode> topics;
  final String? parentLabel;
  final ValueChanged<TopicNode> onStart;
  final ValueChanged<TopicNode> onOpenChildren;
  final int promotedCount;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final entries = _entriesForWidth(constraints.maxWidth);
      return constraints.maxWidth < 600
          ? _PhoneTopicField(
              entries: entries,
              maxWidth: constraints.maxWidth,
              onStart: onStart,
              onOpenChildren: onOpenChildren,
            )
          : _WideTopicField(
              entries: entries,
              maxWidth: constraints.maxWidth,
              onStart: onStart,
              onOpenChildren: onOpenChildren,
            );
    },
  );

  List<_TopicEntry> _entriesForWidth(double width) {
    if (parentLabel != null) {
      return [
        for (final topic in topics)
          _TopicEntry(
            topic: topic,
            parentLabel: parentLabel,
            parentId: topic.parentId ?? parentLabel,
            promoted: true,
          ),
      ];
    }

    // Sub-topics only surface on the root map when they are clearly
    // relevant; weaker ones stay behind their parent's drill-down.
    // Topics with only 1 subtopic are not promoted or drilled into.
    const promotedThreshold = 0.55;
    final promoted =
        topics
            .where(
              (parent) =>
                  (parent.children.isNotEmpty
                      ? parent.children.length
                      : parent.childCount) >
                  1,
            )
            .expand(
              (parent) => parent.children.map(
                (child) => _TopicEntry(
                  topic: child,
                  parentLabel: parent.label,
                  parentId: parent.id,
                  promoted: true,
                ),
              ),
            )
            .where(
              (entry) => _importance(entry.topic.score) >= promotedThreshold,
            )
            .toList(growable: false)
          ..sort((left, right) {
            final score = _importance(
              right.topic.score,
            ).compareTo(_importance(left.topic.score));
            return score != 0
                ? score
                : left.topic.label.compareTo(right.topic.label);
          });
    final selectedChildren = promoted
        .take(math.min(promotedLimit(width), promoted.length))
        .toList();

    return [
      for (final parent in topics) ...[
        _TopicEntry(topic: parent),
        ...selectedChildren.where((entry) => entry.parentId == parent.id),
      ],
    ];
  }

  int promotedLimit(double width) => switch (width) {
    < 360 => math.min(promotedCount, 2),
    < 600 => math.min(promotedCount, 4),
    _ => promotedCount,
  };
}

class _PhoneTopicField extends StatelessWidget {
  const _PhoneTopicField({
    required this.entries,
    required this.maxWidth,
    required this.onStart,
    required this.onOpenChildren,
  });

  final List<_TopicEntry> entries;
  final double maxWidth;
  final ValueChanged<TopicNode> onStart;
  final ValueChanged<TopicNode> onOpenChildren;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    if (entries.length == 1) {
      return Padding(
        key: const ValueKey('topic_field_vertical'),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: _TopicEntryButton(
              entry: entries.first,
              compact: true,
              onStart: onStart,
              onOpenChildren: onOpenChildren,
            ),
          ),
        ),
      );
    }

    final leftCol = <_TopicEntry>[];
    final rightCol = <_TopicEntry>[];

    for (var i = 0; i < entries.length; i++) {
      if (i.isEven) {
        leftCol.add(entries[i]);
      } else {
        rightCol.add(entries[i]);
      }
    }

    const gap = 8.0;

    return Padding(
      key: const ValueKey('topic_field_vertical'),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in leftCol)
                  Padding(
                    padding: const EdgeInsets.only(bottom: gap),
                    child: _TopicEntryButton(
                      entry: entry,
                      compact: true,
                      onStart: onStart,
                      onOpenChildren: onOpenChildren,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in rightCol)
                  Padding(
                    padding: const EdgeInsets.only(bottom: gap),
                    child: _TopicEntryButton(
                      entry: entry,
                      compact: true,
                      onStart: onStart,
                      onOpenChildren: onOpenChildren,
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

class _WideTopicField extends StatelessWidget {
  const _WideTopicField({
    required this.entries,
    required this.maxWidth,
    required this.onStart,
    required this.onOpenChildren,
  });

  final List<_TopicEntry> entries;
  final double maxWidth;
  final ValueChanged<TopicNode> onStart;
  final ValueChanged<TopicNode> onOpenChildren;

  @override
  Widget build(BuildContext context) {
    final columns = maxWidth >= 940 ? 4 : 3;
    final rows = (entries.length / columns).ceil();
    final cellWidth = maxWidth / columns;
    const rowHeight = 154.0;
    return SizedBox(
      key: const ValueKey('topic_field_horizontal'),
      height: math.max(350, rows * rowHeight + 46),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var index = 0; index < entries.length; index++)
            Positioned(
              left: _left(index, columns, cellWidth, entries[index]),
              top: _top(index, columns, entries[index]),
              width: _width(cellWidth, entries[index]),
              child: _TopicEntryButton(
                entry: entries[index],
                onStart: onStart,
                onOpenChildren: onOpenChildren,
              ),
            ),
        ],
      ),
    );
  }

  double _width(double cellWidth, _TopicEntry entry) {
    final importance = _importance(entry.topic.score);
    final factor = entry.promoted
        ? 0.58 + importance * 0.2
        : 0.5 + importance * 0.42;
    return (cellWidth * factor).clamp(entry.promoted ? 130 : 122, 320);
  }

  double _left(int index, int columns, double cellWidth, _TopicEntry entry) {
    final column = index % columns;
    final width = _width(cellWidth, entry);
    final jitter = ((_stableHash(entry.topic.id) % 31) - 15).toDouble();
    return (column * cellWidth + (cellWidth - width) / 2 + jitter).clamp(
      0,
      columns * cellWidth - width,
    );
  }

  double _top(int index, int columns, _TopicEntry entry) {
    final row = index ~/ columns;
    const wave = <double>[12, 48, 3, 34, 20];
    final jitter = ((_stableHash(entry.topic.id) % 19) - 9).toDouble();
    return row * 154 +
        wave[index % wave.length] +
        jitter +
        (entry.promoted ? 7 : 0);
  }
}

class _TopicEntryButton extends StatelessWidget {
  const _TopicEntryButton({
    required this.entry,
    required this.onStart,
    required this.onOpenChildren,
    this.compact = false,
  });

  final _TopicEntry entry;
  final ValueChanged<TopicNode> onStart;
  final ValueChanged<TopicNode> onOpenChildren;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final effectiveChildCount = entry.topic.children.isNotEmpty
        ? entry.topic.children.length
        : entry.topic.childCount;
    final hasMultipleSubtopics = effectiveChildCount > 1;

    return TopicButton(
      topic: entry.topic,
      parentLabel: entry.parentLabel,
      colorSeed: entry.parentId,
      promoted: entry.promoted,
      compact: compact,
      onStart: () => onStart(entry.topic),
      onOpenChildren: hasMultipleSubtopics
          ? () => onOpenChildren(entry.topic)
          : null,
    );
  }
}

class _TopicEntry {
  const _TopicEntry({
    required this.topic,
    this.parentLabel,
    this.parentId,
    this.promoted = false,
  });

  final TopicNode topic;
  final String? parentLabel;
  final String? parentId;
  final bool promoted;
}

double _importance(double score) =>
    score > 1 ? (score / 100).clamp(0, 1) : score.clamp(0, 1);

int _stableHash(String value) =>
    value.runes.fold(17, (hash, rune) => (hash * 31 + rune) & 0x7fffffff);
