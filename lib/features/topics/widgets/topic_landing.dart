import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/style.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/style_provider.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_breadcrumbs.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_field.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_starter_card.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_switch_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

AppLocalizations _l10n(BuildContext c) =>
    AppLocalizations.of(c) ?? lookupAppLocalizations(const Locale('en'));

class TopicLanding extends StatefulWidget {
  const TopicLanding({
    super.key,
    required this.conversationId,
    required this.onStarterSelected,
  });
  final String conversationId;
  final ValueChanged<String> onStarterSelected;
  @override
  State<TopicLanding> createState() => _TopicLandingState();
}

class _TopicLandingState extends State<TopicLanding> {
  late final TextEditingController _searchController;
  TopicDiscoveryProvider? _topics;

  /// The [TopicDiscoveryProvider.newTopicEpoch] this state last seeded for.
  int _seededEpoch = -1;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<TopicDiscoveryProvider>().load());
      _maybeSeedNewTopicDefaults();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final topics = context.read<TopicDiscoveryProvider>();
    if (!identical(topics, _topics)) {
      _topics?.removeListener(_onTopicsChanged);
      _topics = topics;
      topics.addListener(_onTopicsChanged);
    }
  }

  @override
  void dispose() {
    _topics?.removeListener(_onTopicsChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onTopicsChanged() => _maybeSeedNewTopicDefaults();

  /// Claim the current epoch before the async seed starts: `load()` notifies
  /// synchronously, and without claiming first the listener and the post-frame
  /// callback would start two seeds for the same window.
  void _maybeSeedNewTopicDefaults() {
    final topics = _topics;
    if (topics == null || topics.newTopicEpoch == _seededEpoch) return;
    _seededEpoch = topics.newTopicEpoch;
    unawaited(_seedNewTopicDefaults());
  }

  /// A new-topic window composes a clean slate: the user's default style
  /// (or last-used fallback) is selected, thinking starts at the style's own
  /// level or Medium, and the primary conversation adopts those settings so
  /// topic chats and landing sends use them too. Runs on startup and every
  /// New topic action; providers are optional so isolated widget tests that
  /// mount the landing alone keep working.
  Future<void> _seedNewTopicDefaults() async {
    final topics = _topics;
    if (topics == null || !mounted) return;
    final epoch = topics.newTopicEpoch;

    // Styles are the heart of the seed; without the provider there is nothing
    // to do. Model/chat are only needed to apply the seed to the primary, so
    // they are read separately — isolated widget tests may mount the landing
    // with only the providers they exercise.
    final StyleProvider styles;
    try {
      styles = context.read<StyleProvider>();
    } catch (_) {
      return;
    }
    final seed = await styles.applyDefaultForNewTopic();
    if (!mounted || (_topics?.newTopicEpoch ?? epoch) != epoch) return;

    final ModelProvider models;
    final ChatProvider chat;
    try {
      models = context.read<ModelProvider>();
      chat = context.read<ChatProvider>();
    } catch (_) {
      return;
    }
    await models.ensureLoaded();
    if (!mounted || (_topics?.newTopicEpoch ?? epoch) != epoch) return;
    await _applySeedToPrimary(chat, models, styles, seed);
  }

  Future<void> _applySeedToPrimary(
    ChatProvider chat,
    ModelProvider models,
    StyleProvider styles,
    Style? seed,
  ) async {
    // The style's model only applies when the model is installed; otherwise
    // keep the current selection and still apply its prompt/thinking.
    final modelId =
        seed != null && models.availableModels.any((m) => m.id == seed.modelId)
        ? seed.modelId
        : null;
    if (modelId != null) models.selectModel(modelId);

    final conversation = chat.currentConversation;
    if (conversation == null || !conversation.isPrimary) return;
    final thinking = styles.pendingThinkingLevel;
    final prompt = styles.pendingSystemPrompt;
    final modelChanged = modelId != null && conversation.model != modelId;
    final thinkingChanged = conversation.thinkingLevel != thinking;
    final promptChanged =
        (conversation.systemPrompt?.trim() ?? '') != (prompt ?? '');
    if (!modelChanged && !thinkingChanged && !promptChanged) return;
    await chat.updateConversation(
      model: modelChanged ? modelId : null,
      thinkingLevel: thinking,
      setThinkingLevel: true,
      systemPrompt: prompt,
      clearSystemPrompt: prompt == null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TopicDiscoveryProvider>();
    final l10n = _l10n(context);
    final topics = p.visibleTopics;
    final parentLabel = p.searchQuery.isEmpty ? p.path.lastOrNull?.label : null;
    final starters = p.selectedTopic?.starterPrompts ?? const <String>[];
    Widget body;
    if (p.loading && topics.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      );
    } else if (p.error != null && topics.isEmpty) {
      body = _LandingNotice(
        icon: Icons.cloud_off_outlined,
        text: _localizedTopicError(context, p.error!),
        onRetry: () => p.load(force: true),
      );
    } else if (topics.isEmpty) {
      body = _LandingNotice(
        icon: Icons.chat_bubble_outline,
        text: l10n.topicEmpty,
      );
    } else {
      body = TopicField(
        topics: topics,
        parentLabel: parentLabel,
        promotedCount: p.promotedCount,
        onStart: (t) async {
          ChatProvider? chat;
          try {
            chat = Provider.of<ChatProvider>(context, listen: false);
          } catch (_) {
            chat = null;
          }
          final currentTopic = p.selectedTopic;
          if (chat != null &&
              chat.messages.isNotEmpty &&
              currentTopic != null &&
              currentTopic.id.isNotEmpty &&
              currentTopic.id != t.id) {
            await TopicSwitchConfirmationDialog.show(
              context,
              conversationId: widget.conversationId,
              targetTopic: t,
            );
            return;
          }
          await p.activate(widget.conversationId, t);
        },
        onOpenChildren: p.openChildren,
      );
    }

    return Semantics(
      container: true,
      label: l10n.chooseConversationTopic,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xff14161c)
                  : Colors.white,
            ),
          ),
          const Positioned.fill(child: _LandingAtmosphere()),
          Positioned.fill(
            child: SingleChildScrollView(
              key: const ValueKey('topic_landing'),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    children: [
                      _ModeSelector(
                        mode: p.mode,
                        onSelect: (m) => unawaited(p.setMode(m)),
                      ),
                      const SizedBox(height: 8),
                      _TopicSearchBar(
                        controller: _searchController,
                        onChanged: p.setSearchQuery,
                        onClear: () {
                          _searchController.clear();
                          p.setSearchQuery('');
                        },
                      ),
                      if (p.path.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        TopicBreadcrumbs(
                          path: p.path,
                          onSelected: p.goToPathIndex,
                        ),
                      ],
                      const SizedBox(height: 16),
                      body,
                      if (p.mode == TopicOrigin.explore) ...[
                        const SizedBox(height: 18),
                        _SomethingNewButton(
                          onTap: () => p.activateFreeText(
                            widget.conversationId,
                            l10n.somethingNew,
                          ),
                        ),
                      ],
                      if (starters.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _PromptCard(
                          starters: starters,
                          onSelected: widget.onStarterSelected,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onSelect});
  final TopicOrigin mode;
  final ValueChanged<TopicOrigin> onSelect;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = _l10n(context);
    return Center(
      child: Container(
        key: const ValueKey('topic_mode_selector'),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? cs.surfaceContainerHighest
              : cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeButton(
              key: const ValueKey('topic_mode_personal'),
              icon: Icons.history_rounded,
              label: l10n.personal,
              selected: mode == TopicOrigin.personal,
              onTap: () => onSelect(TopicOrigin.personal),
            ),
            _ModeButton(
              key: const ValueKey('topic_mode_explore'),
              icon: Icons.explore_outlined,
              label: l10n.explore,
              selected: mode == TopicOrigin.explore,
              onTap: () => onSelect(TopicOrigin.explore),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.surface : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      elevation: selected ? 1 : 0,
      shadowColor: cs.shadow.withValues(alpha: 0.15),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Color.lerp(cs.primary, cs.onSurface, 0.25)
                      : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SomethingNewButton extends StatelessWidget {
  const _SomethingNewButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = _l10n(context);
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        key: const ValueKey('something_new_topic'),
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_comment_outlined, size: 15, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                l10n.somethingNew,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color.lerp(cs.primary, cs.onSurface, 0.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.starters, required this.onSelected});
  final List<String> starters;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.13),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 29,
                height: 29,
                decoration: BoxDecoration(
                  color: cs.tertiary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 17,
                  color: cs.tertiary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _l10n(context).topicFocusHint,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final s in starters.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: TopicStarterCard(text: s, onTap: () => onSelected(s)),
            ),
        ],
      ),
    );
  }
}

class _LandingNotice extends StatelessWidget {
  const _LandingNotice({required this.icon, required this.text, this.onRetry});
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 26, color: cs.primary),
          ),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: Text(_l10n(context).tryAgain),
            ),
          ],
        ],
      ),
    );
  }
}

String _localizedTopicError(BuildContext c, String e) => switch (e) {
  'Topics are temporarily unavailable' => _l10n(c).messageCouldNotReachServer,
  'Historical context is temporarily limited' => _l10n(
    c,
  ).historicalContextLimited,
  _ => e,
};

class _LandingAtmosphere extends StatelessWidget {
  const _LandingAtmosphere();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.1),
            radius: 1.1,
            colors: [cs.primary.withValues(alpha: 0.07), Colors.transparent],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.68, 0.44),
              radius: 0.85,
              colors: [cs.tertiary.withValues(alpha: 0.06), Colors.transparent],
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.84, -0.3),
                radius: 0.75,
                colors: [
                  const Color(0xff1d8865).withValues(alpha: 0.06),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicSearchBar extends StatelessWidget {
  const _TopicSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: const ValueKey('topic_search_bar'),
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.symmetric(vertical: 6),
      height: 40,
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? cs.surfaceContainerHighest.withValues(alpha: 0.6)
            : cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: TextField(
        key: const ValueKey('topic_search_input'),
        controller: controller,
        onChanged: onChanged,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: 'Search topics...',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          prefixIcon: Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
          suffixIcon: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => controller.text.isNotEmpty
                ? IconButton(
                    key: const ValueKey('topic_search_clear'),
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: onClear,
                  )
                : const SizedBox.shrink(),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
      ),
    );
  }
}
