import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/reading_column.dart';
import 'package:garbanzo_ai/core/widgets/fade_slide_in.dart';
import 'package:garbanzo_ai/features/chat/models/agent_liveness.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/utils/agent_progress_builder.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_message_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/context_summary_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/empty_chat_state.dart';
import 'package:garbanzo_ai/features/chat/widgets/progress/agent_progress_card.dart';
import 'package:garbanzo_ai/features/chat/widgets/system_prompt_banner.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_context_empty_state.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_landing.dart';

/// Renders the conversation transcript, empty/landing states, tool-activity
/// groups, and live streaming message anchor.
class ChatTranscriptView extends StatelessWidget {
  const ChatTranscriptView({
    super.key,
    required this.scrollController,
    required this.streamAnchorKey,
    required this.onOpenActiveContext,
    required this.onStarterFromLanding,
  });

  final ScrollController scrollController;
  final GlobalKey streamAnchorKey;
  final VoidCallback onOpenActiveContext;
  final ValueChanged<String> onStarterFromLanding;

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final conversation = chatProvider.currentConversation;
    final topicDiscovery = context.watch<TopicDiscoveryProvider>();
    if (conversation?.isPrimary == true && topicDiscovery.showLanding) {
      return TopicLanding(
        conversationId: conversation!.id,
        onStarterSelected: onStarterFromLanding,
      );
    }
    if (chatProvider.messages.isEmpty &&
        chatProvider.currentConversation == null) {
      return EmptyChatState(
        onSendMessage: (msg) => chatProvider.sendMessage(msg),
      );
    }

    final hasUserMessages = chatProvider.messages.any((m) => m.role == 'user');

    final activeTopic =
        conversation?.activeTopic ??
        (conversation?.activeTopicId != null &&
                topicDiscovery.selectedTopic?.id == conversation?.activeTopicId
            ? topicDiscovery.selectedTopic
            : (conversation?.activeTopicId != null
                  ? TopicNode(
                      id: conversation!.activeTopicId!,
                      label: conversation.title ?? 'Topic',
                      origin: TopicOrigin.history,
                      description: conversation.contextSummary,
                      starterPrompts: [
                        'Continue with ${conversation.title ?? 'Topic'}',
                        'What should I do next about ${conversation.title ?? 'Topic'}?',
                      ],
                    )
                  : null));

    if (!hasUserMessages && activeTopic != null && conversation != null) {
      return TopicContextEmptyState(
        conversationId: conversation.id,
        topic: activeTopic,
        onStarterSelected: (message) => chatProvider.sendMessage(message),
        onOpenContext: onOpenActiveContext,
      );
    }

    if (chatProvider.messages.isEmpty && chatProvider.isLoadingConversations) {
      return const Center(child: CircularProgressIndicator());
    }

    final showSystemPrompt = context.watch<SettingsProvider>().showSystemPrompt;
    final isTopicChat =
        chatProvider.currentConversation?.isPrimary == true ||
        chatProvider.currentConversation?.activeTopicId != null ||
        topicDiscovery.selectedTopic != null;
    final summary = isTopicChat
        ? null
        : chatProvider.currentConversation?.contextSummary;
    final hasSummary = summary != null && summary.isNotEmpty;
    final hasBanner =
        showSystemPrompt && chatProvider.currentConversation != null;
    // B-03: a spinner above the oldest loaded message while an older page
    // fetched via scroll-to-top is in flight.
    final showLoadingOlder = chatProvider.loadingOlderMessages;

    var itemOffset = 0;
    if (showLoadingOlder) itemOffset++;
    if (hasBanner) itemOffset++;
    if (hasSummary) itemOffset++;

    // Group consecutive tool_call/tool_result messages so they render as a
    // single collapsible "tool activity" section instead of N stacked cards.
    final items = <_ListItem>[];
    final visualCallIds = {
      for (final message in chatProvider.messages)
        if (message.visualPresentation != null) message.toolCallId,
    };
    final messages = chatProvider.messages.where((message) {
      final calls = message.metadata?['tool_calls'];
      // Successful presentation calls are already represented by their visual
      // answer. Preserve failed calls and ordinary tool activity for inspection.
      return !(message.isToolCall &&
          calls is List &&
          calls.isNotEmpty &&
          calls.every(
            (call) => call is Map && visualCallIds.contains(call['id']),
          ));
    }).toList();
    // A proposal tool's result is a card the user acts on, not a step in the
    // agent's timeline — folding it into the collapsible "Used N tools"
    // section would bury it (and make ChatMessageWidget's card branch
    // unreachable), so it stays a top-level item.
    bool isGroupableTool(ChatMessage m) =>
        (m.isToolCall || m.isToolResult) &&
        m.actionProposal == null &&
        m.visualPresentation == null;

    var i = 0;
    var lastAssistantIdx = -1;
    for (var j = 0; j < messages.length; j++) {
      if (messages[j].isAssistant) lastAssistantIdx = j;
    }
    while (i < messages.length) {
      final m = messages[i];
      if (isGroupableTool(m)) {
        final start = i;
        while (i < messages.length && isGroupableTool(messages[i])) {
          i++;
        }
        items.add(_ToolGroupItem(messages.sublist(start, i), endIdx: i - 1));
      } else {
        items.add(_MessageItem(m, idx: i));
        i++;
      }
    }

    // Every list item lives in a centered reading column so wide desktop
    // windows don't stretch prose to unreadable line lengths.
    Widget centered(Widget child) => ReadingColumn(child: child);

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: items.length + itemOffset,
      itemBuilder: (context, index) {
        var leadingIdx = 0;
        if (showLoadingOlder) {
          if (index == leadingIdx) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          leadingIdx++;
        }
        if (hasBanner) {
          if (index == leadingIdx) return centered(const SystemPromptBanner());
          leadingIdx++;
        }
        if (hasSummary) {
          if (index == leadingIdx) {
            return centered(ContextSummaryWidget(summary: summary));
          }
        }
        final item = items[index - itemOffset];
        if (item is _ToolGroupItem) {
          // The streaming assistant placeholder stays anchored after tool
          // messages, so an active tool group is technically penultimate.
          // Treat it as live while everything after it is that still-empty
          // placeholder; once answer text arrives the activity is complete.
          final messagesAfter = messages.skip(item.endIdx + 1);
          final isActive =
              chatProvider.isSending &&
              messagesAfter.every(
                (message) =>
                    message.id == chatProvider.streamingMessageId &&
                    message.isAssistant &&
                    message.content.isEmpty,
              );
          return FadeSlideIn(
            child: centered(
              // Subscribes to the liveness channel directly: heartbeats arrive
              // seconds apart and must repaint only this object, never the
              // whole transcript.
              ValueListenableBuilder<AgentLiveness?>(
                valueListenable: chatProvider.agentLiveness,
                builder: (context, liveness, _) => _LiveAgentProgress(
                  messages: item.messages,
                  live: isActive,
                  liveness: liveness,
                ),
              ),
            ),
          );
        }
        final messageItem = item as _MessageItem;
        final message = messageItem.message;
        final msgIdx = messageItem.idx;
        final isLastMessage = msgIdx == messages.length - 1;

        Widget buildBubble(ChatMessage m) => FadeSlideIn(
          child: centered(
            ChatMessageWidget(
              message: m,
              isStreaming:
                  isLastMessage && chatProvider.isSending && m.isAssistant,
              conversationId: chatProvider.currentConversation?.id,
              isLastAssistant: m.isAssistant && msgIdx == lastAssistantIdx,
              onOpenTopicContext: onOpenActiveContext,
            ),
          ),
        );

        // The in-flight assistant bubble subscribes to the streaming
        // channel directly, so per-chunk updates repaint only this one
        // widget instead of the whole list. The anchor key lets the smart
        // scroll helper locate the bubble to chase/pin it while streaming.
        if (message.id == chatProvider.streamingMessageId) {
          return KeyedSubtree(
            key: streamAnchorKey,
            child: ValueListenableBuilder<ChatMessage?>(
              valueListenable: chatProvider.streamingMessage,
              builder: (context, live, _) => buildBubble(
                live != null && live.id == message.id ? live : message,
              ),
            ),
          );
        }
        return buildBubble(message);
      },
    );
  }
}

/// Builds the agent progress object from a tool group's messages plus the live
/// liveness channel.
///
/// Split out so the (cheap) message fold and the (frequent) liveness update stay
/// separable: heartbeats repaint only through the ValueListenableBuilder that
/// owns this widget, never the whole transcript.
class _LiveAgentProgress extends StatelessWidget {
  const _LiveAgentProgress({
    required this.messages,
    required this.live,
    required this.liveness,
  });

  final List<ChatMessage> messages;
  final bool live;
  final AgentLiveness? liveness;

  @override
  Widget build(BuildContext context) {
    final progress = AgentProgressBuilder.fromMessages(
      messages,
      live: live,
      startedAt: liveness?.startedAt,
      heartbeatActivity: liveness?.activity,
      heartbeatElapsedSeconds: liveness?.elapsedSeconds,
      secondsSinceSignal: liveness?.secondsSinceSignal,
      completedCount: liveness?.completedCount,
    );
    return AgentProgressCard(progress: progress, dense: true);
  }
}

sealed class _ListItem {
  const _ListItem();
}

class _MessageItem extends _ListItem {
  const _MessageItem(this.message, {required this.idx});
  final ChatMessage message;
  final int idx;
}

class _ToolGroupItem extends _ListItem {
  const _ToolGroupItem(this.messages, {required this.endIdx});
  final List<ChatMessage> messages;
  final int endIdx;
}
