import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/motion.dart';
import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/models/style.dart';
import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/chat/widgets/styles/style_picker_helpers.dart';
import 'package:garbanzo_ai/features/friends/widgets/share_with_friend_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// The Styles segment body: the user's own saved styles first under a
/// "Your styles" header, then the read-only built-in styles under "Predefined".
class StylesSegment extends StatelessWidget {
  const StylesSegment({
    super.key,
    required this.isLoading,
    required this.styles,
    required this.styleIsActive,
    required this.models,
    required this.templates,
    required this.busy,
    required this.onApply,
    required this.onSetDefault,
    required this.onEdit,
    required this.onDelete,
    required this.onCreate,
    required this.showCreateTile,
  });

  final bool isLoading;
  final List<Style> styles;
  final bool Function(Style) styleIsActive;
  final List<ModelInfo> models;
  final List<SystemPromptTemplate> templates;
  final bool busy;
  final void Function(Style) onApply;
  final void Function(Style, bool) onSetDefault;
  final void Function(Style) onEdit;
  final void Function(Style) onDelete;
  final VoidCallback onCreate;
  final bool showCreateTile;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final predefined = styles.where((s) => s.isBuiltin).toList();
    final custom = styles.where((s) => !s.isBuiltin).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(label: l.labelYourStyles),
        if (custom.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(
              l.messageNoSavedStylesYet,
              key: const ValueKey('custom_styles_empty'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...custom.map((s) => _styleCard(context, s)),
        if (showCreateTile) _NewStyleTile(onTap: busy ? null : onCreate),
        if (predefined.isNotEmpty) ...[
          _SectionHeader(label: l.labelPredefinedStyles),
          ...predefined.map((s) => _styleCard(context, s)),
        ],
      ],
    );
  }

  Widget _styleCard(BuildContext context, Style s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _StyleCard(
        key: ValueKey('style_card_${s.id}'),
        style: s,
        active: styleIsActive(s),
        modelName: models.where((m) => m.id == s.modelId).firstOrNull?.name,
        templateName: templates
            .where((t) => t.id == s.systemPromptTemplateId)
            .firstOrNull
            ?.name,
        enabled: !busy,
        onTap: () => onApply(s),
        onSetDefault: (v) => onSetDefault(s, v),
        onEdit: () => onEdit(s),
        onDelete: () => onDelete(s),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        label,
        key: ValueKey('styles_section_header_$label'),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    super.key,
    required this.style,
    required this.active,
    required this.modelName,
    required this.templateName,
    required this.enabled,
    required this.onTap,
    required this.onSetDefault,
    required this.onEdit,
    required this.onDelete,
  });

  final Style style;
  final bool active;
  final String? modelName;
  final String? templateName;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<bool> onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final available = modelName != null;
    final monogram = styleMonogram(style.name);
    final composition = styleComposition(style, modelName, templateName);
    final subtitle = style.isBuiltin
        ? (style.description ?? composition)
        : composition;

    return AnimatedContainer(
      duration: Motion.fast,
      decoration: BoxDecoration(
        color: active
            ? colorScheme.secondaryContainer.withValues(alpha: 0.55)
            : colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? colorScheme.primary : colorScheme.outlineVariant,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: active
                      ? colorScheme.primary
                      : colorScheme.primaryContainer,
                  child: Text(
                    monogram,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: active
                          ? colorScheme.onPrimary
                          : colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              style.name,
                              style: theme.textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (style.isDefault) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: AppLocalizations.of(
                                context,
                              )!.usedForNewChats,
                              child: Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!available)
                  Tooltip(
                    message: '${style.modelId} is not installed',
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: colorScheme.error,
                    ),
                  ),
                PopupMenuButton<String>(
                  tooltip: AppLocalizations.of(context)!.tooltipStyleOptions,
                  iconSize: 18,
                  onSelected: (action) {
                    switch (action) {
                      case 'default':
                        onSetDefault(!style.isDefault);
                      case 'edit':
                        onEdit();
                      case 'share':
                        showShareWithFriendDialog(
                          context,
                          kind: 'style',
                          itemId: style.id,
                          itemName: style.name,
                        );
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'default',
                      child: Text(
                        style.isDefault
                            ? 'Stop using for new chats'
                            : 'Use for new chats',
                      ),
                    ),
                    if (!style.isBuiltin) ...[
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(AppLocalizations.of(context)!.editEllipsis),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(AppLocalizations.of(context)!.delete),
                      ),
                    ],
                    PopupMenuItem(
                      value: 'share',
                      child: Text(
                        AppLocalizations.of(context)!.shareWithAFriend,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewStyleTile extends StatelessWidget {
  const _NewStyleTile({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onTap != null;
    final color = enabled
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: color.withValues(alpha: 0.6),
            radius: 12,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, size: 20, color: color),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.styleNew,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    const dashWidth = 6.0;
    const dashGap = 4.0;
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
