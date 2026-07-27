import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/chat/models/agent_activity.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/widgets/agent_activity_labels.dart';
import 'package:garbanzo_ai/features/chat/widgets/tool_bubble_widget.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// A compact, human-readable timeline for a run of agent tool activity.
///
/// The collapsed card describes the current milestone instead of exposing a
/// raw tool name. Expanding it reveals grounded actions (files reviewed,
/// source updated, checks run); raw inputs and outputs remain available under
/// Technical details for debugging.
class ToolActivityGroup extends StatefulWidget {
  const ToolActivityGroup({
    super.key,
    required this.messages,
    this.isStreaming = false,
  });

  final List<ChatMessage> messages;
  final bool isStreaming;

  @override
  State<ToolActivityGroup> createState() => _ToolActivityGroupState();
}

class _ToolActivityGroupState extends State<ToolActivityGroup> {
  late bool _isExpanded;
  bool _showTechnicalDetails = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isStreaming && _activity.isMicroApp;
  }

  AgentActivityGroup get _activity =>
      AgentActivityGroup.fromMessages(widget.messages);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final activity = _activity;
    final live = widget.isStreaming;
    final title = agentActivityTitle(activity, l10n, live: live);
    final current = activity.currentStep;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colors.primaryContainer.withValues(alpha: live ? 0.44 : 0.24),
              colors.surfaceContainerLow.withValues(alpha: 0.7),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (live ? colors.primary : colors.outlineVariant).withValues(
              alpha: live ? 0.35 : 0.55,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Row(
                    children: [
                      _ActivityIcon(
                        live: live,
                        isMicroApp: activity.isMicroApp,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: live ? colors.primary : colors.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (current != null) ...[
                              const SizedBox(height: 2),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: Text(
                                  agentActivityStepLabel(
                                    current,
                                    l10n,
                                    active: live && !current.done,
                                  ),
                                  key: ValueKey(
                                    '${current.callId}-${current.done}',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (live)
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: _isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.expand_more,
                          size: 20,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !_isExpanded
                    ? const SizedBox(width: double.infinity)
                    : _ActivityDetails(
                        activity: activity,
                        isStreaming: live,
                        showTechnicalDetails: _showTechnicalDetails,
                        onToggleTechnicalDetails: () => setState(
                          () => _showTechnicalDetails = !_showTechnicalDetails,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityIcon extends StatelessWidget {
  const _ActivityIcon({required this.live, required this.isMicroApp});

  final bool live;
  final bool isMicroApp;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: live ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        isMicroApp ? Icons.auto_awesome_outlined : Icons.route_outlined,
        size: 19,
        color: live ? colors.primary : colors.onSurfaceVariant,
      ),
    );
  }
}

class _ActivityDetails extends StatelessWidget {
  const _ActivityDetails({
    required this.activity,
    required this.isStreaming,
    required this.showTechnicalDetails,
    required this.onToggleTechnicalDetails,
  });

  final AgentActivityGroup activity;
  final bool isStreaming;
  final bool showTechnicalDetails;
  final VoidCallback onToggleTechnicalDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final visibleSteps = activity.steps.isEmpty
        ? <AgentActivityStep>[activity.fallbackStep]
        : activity.steps;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: colors.outlineVariant.withValues(alpha: 0.6)),
          const SizedBox(height: 4),
          for (var i = 0; i < visibleSteps.length; i++)
            _ActivityStepRow(
              step: visibleSteps[i],
              active: isStreaming && i == visibleSteps.length - 1,
              isLast: i == visibleSteps.length - 1,
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onToggleTechnicalDetails,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: Icon(
              showTechnicalDetails ? Icons.expand_less : Icons.code,
              size: 16,
            ),
            label: Text(l10n.agentActivityTechnicalDetails),
          ),
          if (showTechnicalDetails)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < activity.messages.length; i++)
                    ToolBubbleWidget(
                      message: activity.messages[i],
                      isStreaming:
                          isStreaming &&
                          i == activity.messages.length - 1 &&
                          activity.messages[i].isToolCall,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityStepRow extends StatelessWidget {
  const _ActivityStepRow({
    required this.step,
    required this.active,
    required this.isLast,
  });

  final AgentActivityStep step;
  final bool active;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final running = active && !step.done;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                const SizedBox(height: 5),
                if (running)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: colors.primary,
                    ),
                  )
                else
                  Icon(
                    step.failed ? Icons.error_outline : Icons.check_circle,
                    size: 16,
                    color: step.failed ? colors.error : colors.primary,
                  ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: colors.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                agentActivityStepLabel(step, l10n, active: running),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: step.failed ? colors.error : colors.onSurface,
                  fontWeight: running ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
