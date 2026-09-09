import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/models/topic_switch.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';
import 'package:uuid/uuid.dart';

/// Confirmation dialog presenting Combine, Switch, or Cancel options.
class TopicSwitchConfirmationDialog extends StatefulWidget {
  const TopicSwitchConfirmationDialog({
    super.key,
    required this.conversationId,
    required this.targetTopic,
  });

  final String conversationId;
  final TopicNode targetTopic;

  static Future<TopicSwitchResponse?> show(
    BuildContext context, {
    required String conversationId,
    required TopicNode targetTopic,
  }) => showDialog<TopicSwitchResponse>(
    context: context,
    builder: (dialogContext) => TopicSwitchConfirmationDialog(
      conversationId: conversationId,
      targetTopic: targetTopic,
    ),
  );

  @override
  State<TopicSwitchConfirmationDialog> createState() =>
      _TopicSwitchConfirmationDialogState();
}

class _TopicSwitchConfirmationDialogState
    extends State<TopicSwitchConfirmationDialog> {
  bool _retainPinned = true;
  bool _submitting = false;
  String? _submittingAction;
  String? _errorMessage;
  String? _switchIdempotencyKey;
  String? _combineIdempotencyKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('en'));
    final topics = context.watch<TopicDiscoveryProvider>();
    final currentTopic = topics.selectedTopic;
    final hasCurrent =
        currentTopic != null &&
        currentTopic.label.isNotEmpty &&
        currentTopic.id != widget.targetTopic.id;

    return AlertDialog(
      key: const ValueKey('topic_switch_dialog'),
      actionsOverflowButtonSpacing: 8,
      title: Row(
        children: [
          Icon(Icons.alt_route_rounded, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.topicSwitchDialogTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                _badge(
                  context,
                  label: widget.targetTopic.label,
                  icon: Icons.topic_outlined,
                  isTarget: true,
                ),
                if (hasCurrent) ...[
                  Text(
                    l10n.topicSwitchWith,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  _badge(
                    context,
                    label: currentTopic.label,
                    icon: Icons.chat_bubble_outline_rounded,
                    isTarget: false,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              hasCurrent
                  ? l10n.topicSwitchChoiceDescription
                  : l10n.topicSwitchStartDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const ValueKey('topic_switch_retain_pinned_checkbox'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _retainPinned,
              onChanged: _submitting || _switchIdempotencyKey != null
                  ? null
                  : (v) => setState(() => _retainPinned = v ?? true),
              title: Text(
                l10n.retainPinnedSourcesOnSwitch,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                style: TextStyle(fontSize: 12, color: cs.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('topic_switch_cancel_button'),
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        OutlinedButton(
          key: const ValueKey('topic_switch_confirm_button'),
          onPressed: _submitting ? null : _handleSwitch,
          child: _submitting && _submittingAction == 'switch'
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.switchTopic),
        ),
        FilledButton.icon(
          key: const ValueKey('topic_switch_combine_button'),
          icon: _submitting && _submittingAction == 'combine'
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.merge_type_rounded, size: 16),
          onPressed: _submitting ? null : _handleCombine,
          label: Text(l10n.combineTopics),
        ),
      ],
    );
  }

  Widget _badge(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isTarget,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isTarget
            ? cs.primaryContainer.withValues(alpha: 0.45)
            : cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isTarget
              ? cs.primary.withValues(alpha: 0.3)
              : cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isTarget ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCombine() async {
    setState(() {
      _submitting = true;
      _submittingAction = 'combine';
      _errorMessage = null;
    });
    try {
      final topics = context.read<TopicDiscoveryProvider>();
      final result = await topics.combineTopics(
        widget.conversationId,
        topicId: widget.targetTopic.id,
        idempotencyKey: _combineIdempotencyKey ??= const Uuid().v4(),
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submittingAction = null;
          _errorMessage =
              '${AppLocalizations.of(context)!.topicCombineFailed}: ${e.toString().replaceAll('Exception: ', '')}';
        });
      }
    }
  }

  Future<void> _handleSwitch() async {
    setState(() {
      _submitting = true;
      _submittingAction = 'switch';
      _errorMessage = null;
    });
    try {
      final topics = context.read<TopicDiscoveryProvider>();
      final result = await topics.switchTopic(
        widget.conversationId,
        topicId: widget.targetTopic.id,
        retainPinned: _retainPinned,
        idempotencyKey: _switchIdempotencyKey ??= const Uuid().v4(),
        mode: 'switch',
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submittingAction = null;
          _errorMessage =
              '${AppLocalizations.of(context)!.topicSwitchFailed}: ${e.toString().replaceAll('Exception: ', '')}';
        });
      }
    }
  }
}
