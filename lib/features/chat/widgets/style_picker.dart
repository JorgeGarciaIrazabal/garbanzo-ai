import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/motion.dart';
import 'package:garbanzo_ai/core/responsive.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/style_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/chat/utils/composer_conversation.dart';
import 'package:garbanzo_ai/features/chat/widgets/styles/style_picker_helpers.dart';
import 'package:garbanzo_ai/features/chat/widgets/styles/style_picker_panel.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

export 'package:garbanzo_ai/features/chat/widgets/styles/style_picker_panel.dart';

/// Compact app-bar/composer pill showing the active style name — or, when the
/// effective settings match no saved style, the effective model (and a
/// thinking marker). Opens the style picker on tap.
class StylePickerButton extends StatelessWidget {
  const StylePickerButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final modelP = context.watch<ModelProvider>();
    final styleP = context.watch<StyleProvider>();
    final promptP = context.watch<SystemPromptProvider>();

    final models = modelP.availableModels;
    if (models.isEmpty) return const SizedBox.shrink();

    final conv = composerConversation(context);
    final effectiveId = conv?.model ?? modelP.selectedModelId;
    final effectiveModel = models.where((m) => m.id == effectiveId).firstOrNull;
    final thinking = conv != null
        ? conv.thinkingLevel
        : styleP.pendingThinkingLevel;
    final prompt = normalizeStylePrompt(
      conv != null ? conv.systemPrompt : styleP.pendingSystemPrompt,
    );
    final languageCode = effectiveLanguageCode(context);
    final visibleStyles = styleP.styles
        .where((style) => styleMatchesLocale(style, languageCode))
        .toList();
    final activeStyle = resolveActiveStyle(
      styleP,
      visibleStyles,
      promptP.templates,
      modelId: effectiveId,
      thinkingLevel: thinking,
      systemPrompt: prompt,
    );
    final label =
        activeStyle?.name ?? effectiveModel?.name ?? effectiveId ?? 'Model';
    final monogram = activeStyle == null
        ? null
        : styleMonogram(activeStyle.name);
    final thinkingActive = thinking != null && thinking != ThinkingLevel.off;
    final enabled = !context.watch<ChatProvider>().isSending;
    final fg = enabled
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final wide = context.isWide && !compact;

    return Tooltip(
      message: AppLocalizations.of(context)!.chatStyle,
      child: InkWell(
        key: const ValueKey('style_picker_button'),
        borderRadius: BorderRadius.circular(20),
        onTap: enabled ? () => showStylePicker(context) : null,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 12 : 8,
            vertical: wide ? 8 : 6,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(
              alpha: enabled ? 1 : 0.5,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (monogram != null)
                CircleAvatar(
                  radius: wide ? 9 : 8,
                  backgroundColor: enabled
                      ? colorScheme.primary
                      : colorScheme.primary.withValues(alpha: 0.5),
                  child: Text(
                    monogram,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: wide ? 10 : 9,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.auto_awesome,
                  size: wide ? 16 : 14,
                  color: enabled ? colorScheme.primary : fg,
                ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: wide ? 220 : (compact ? 72 : 160),
                ),
                child: Text(
                  label,
                  style:
                      (wide
                              ? theme.textTheme.labelLarge
                              : theme.textTheme.labelMedium)
                          ?.copyWith(fontWeight: FontWeight.w600, color: fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (thinkingActive && !compact) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.psychology_outlined,
                  size: wide ? 16 : 14,
                  color: fg,
                ),
              ],
              Icon(Icons.arrow_drop_down, size: wide ? 20 : 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens [StylePickerPanel] as an anchored popover on wide layouts and a modal
/// bottom sheet on narrow layouts.
Future<void> showStylePicker(BuildContext context) {
  final chat = context.read<ChatProvider>();
  final models = context.read<ModelProvider>();
  final styles = context.read<StyleProvider>();
  final prompts = context.read<SystemPromptProvider>();
  final topics = context.read<TopicDiscoveryProvider?>();
  final settings = context.read<SettingsProvider?>();
  Widget wrap(Widget c) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: chat),
      ChangeNotifierProvider.value(value: models),
      ChangeNotifierProvider.value(value: styles),
      ChangeNotifierProvider.value(value: prompts),
      if (topics != null) ChangeNotifierProvider.value(value: topics),
      if (settings != null)
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
    ],
    child: c,
  );
  if (context.isWide) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black26,
      transitionDuration: Motion.medium,
      transitionBuilder: (c, a, _, child) {
        final curve = CurvedAnimation(parent: a, curve: Motion.easeOut);
        return FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.02),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, _, _) {
        final screen = MediaQuery.of(dialogContext).size;
        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(
                top: kToolbarHeight + 4,
                right: 12,
              ),
              child: Material(
                color: Theme.of(dialogContext).colorScheme.surfaceContainerLow,
                elevation: 6,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (screen.width * 0.38).clamp(440.0, 560.0),
                    maxHeight: screen.height - kToolbarHeight - 48,
                  ),
                  child: MediaQuery(
                    data: MediaQuery.of(
                      dialogContext,
                    ).copyWith(textScaler: const TextScaler.linear(1.12)),
                    child: wrap(const StylePickerPanel(showCloseButton: true)),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: double.infinity),
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.96,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SafeArea(
          top: false,
          child: wrap(
            const StylePickerPanel(showCloseButton: true, isBottomSheet: true),
          ),
        ),
      ),
    ),
  );
}
