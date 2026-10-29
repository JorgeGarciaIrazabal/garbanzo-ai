import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/topics/models/topic_switch.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

AppLocalizations _l10n(BuildContext c) =>
    AppLocalizations.of(c) ?? lookupAppLocalizations(const Locale('en'));

class TopicArchivesDialog extends StatelessWidget {
  const TopicArchivesDialog({super.key, required this.topicId});

  final String topicId;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final provider = context.watch<TopicDiscoveryProvider>();
    final archives = provider.topicArchives[topicId] ?? const <TopicArchive>[];
    final conversations = provider.topicConversations(topicId);
    final loading = provider.isArchiveListLoading(topicId);
    final error = provider.archiveListError(topicId);
    return AlertDialog(
      key: const ValueKey('topic_archives_dialog'),
      title: Text(l10n.earlierSessions),
      content: SizedBox(
        width: 620,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.earlierSessionsDescription,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: loading && archives.isEmpty && conversations.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.archiveLoadFailed),
                          TextButton(
                            onPressed: () => provider.loadArchives(topicId),
                            child: Text(l10n.retry),
                          ),
                        ],
                      ),
                    )
                  : archives.isEmpty && conversations.isEmpty
                  ? Center(child: Text(l10n.noEarlierSessions))
                  : ListView.separated(
                      itemCount: conversations.length + archives.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (itemContext, index) {
                        if (index < conversations.length) {
                          final conversation = conversations[index];
                          final date = MaterialLocalizations.of(
                            itemContext,
                          ).formatMediumDate(conversation.updatedAt.toLocal());
                          return ListTile(
                            key: ValueKey(
                              'topic_conversation_${conversation.id}',
                            ),
                            leading: const Icon(
                              Icons.chat_bubble_outline_rounded,
                            ),
                            title: Text(
                              conversation.title ?? l10n.archivedSession,
                            ),
                            subtitle: Text(
                              '$date • ${l10n.archiveMessageCount(conversation.messageCount)}',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () =>
                                Navigator.pop(context, conversation.id),
                          );
                        }
                        final archive = archives[index - conversations.length];
                        final date = MaterialLocalizations.of(
                          itemContext,
                        ).formatMediumDate(archive.createdAt.toLocal());
                        return ListTile(
                          key: ValueKey('topic_archive_${archive.id}'),
                          leading: const Icon(Icons.history_rounded),
                          title: Text(
                            archive.shortSummary ?? l10n.archivedSession,
                          ),
                          subtitle: Text(
                            '$date • ${l10n.archiveMessageCount(archive.messageCount)}',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () async {
                            await provider.loadArchivePage(topicId, archive.id);
                            if (!itemContext.mounted) return;
                            final openedId = await showDialog<String>(
                              context: itemContext,
                              builder: (_) => TopicArchiveMessagesDialog(
                                topicId: topicId,
                                archive: archive,
                              ),
                            );
                            if (openedId != null && context.mounted) {
                              Navigator.pop(context, openedId);
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

class TopicArchiveMessagesDialog extends StatefulWidget {
  const TopicArchiveMessagesDialog({
    super.key,
    required this.topicId,
    required this.archive,
  });

  final String topicId;
  final TopicArchive archive;

  @override
  State<TopicArchiveMessagesDialog> createState() =>
      _TopicArchiveMessagesDialogState();
}

class _TopicArchiveMessagesDialogState
    extends State<TopicArchiveMessagesDialog> {
  bool _resuming = false;
  bool _resumeFailed = false;

  Future<void> _resume() async {
    setState(() {
      _resuming = true;
      _resumeFailed = false;
    });
    try {
      final existing = widget.archive.resumedConversationId;
      final conversationId =
          existing ??
          (await context.read<TopicDiscoveryProvider>().resumeArchive(
            widget.topicId,
            widget.archive.id,
          )).id;
      if (mounted) Navigator.pop(context, conversationId);
    } catch (e) {
      debugPrint('TopicArchiveMessagesDialog._resume failed: $e');
      if (mounted) {
        setState(() {
          _resuming = false;
          _resumeFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final provider = context.watch<TopicDiscoveryProvider>();
    final archive = widget.archive;
    final topicId = widget.topicId;
    final page = provider.archivePage(archive.id);
    final loading = provider.isArchiveLoading(archive.id);
    final error = provider.archiveError(archive.id);
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const ValueKey('topic_archive_messages_dialog'),
      title: Text(page?.topicLabel ?? l10n.archivedSession),
      content: SizedBox(
        width: 680,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.archivedSessionContinueDescription,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            if (_resumeFailed)
              Text(l10n.archiveResumeFailed, style: TextStyle(color: cs.error)),
            if (page?.hasMore == true)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('topic_archive_load_older'),
                  onPressed: loading
                      ? null
                      : () => provider.loadArchivePage(
                          topicId,
                          archive.id,
                          older: true,
                        ),
                  icon: loading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_less_rounded),
                  label: Text(l10n.loadOlderMessages),
                ),
              ),
            if (error != null) ...[
              Text(l10n.archiveLoadFailed, style: TextStyle(color: cs.error)),
              TextButton(
                onPressed: loading
                    ? null
                    : () => provider.loadArchivePage(topicId, archive.id),
                child: Text(l10n.retry),
              ),
            ],
            Expanded(
              child: page == null && loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      key: const ValueKey('topic_archive_messages'),
                      itemCount: page?.messages.length ?? 0,
                      itemBuilder: (_, index) {
                        final message = page!.messages[index];
                        final isUser = message.isUser;
                        final speaker = isUser
                            ? l10n.archiveSpeakerYou
                            : message.isAssistant
                            ? l10n.archiveSpeakerGarbanzo
                            : message.role.replaceAll('_', ' ');
                        final timestamp = MaterialLocalizations.of(context)
                            .formatTimeOfDay(
                              TimeOfDay.fromDateTime(
                                message.createdAt.toLocal(),
                              ),
                            );
                        return Card(
                          elevation: 0,
                          color: isUser
                              ? cs.primaryContainer.withValues(alpha: 0.35)
                              : cs.surfaceContainerLow,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$speaker • $timestamp',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(height: 5),
                                SelectableText(message.content),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton.icon(
          key: const ValueKey('topic_archive_resume'),
          onPressed: _resuming ? null : _resume,
          icon: _resuming
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chat_bubble_outline_rounded),
          label: Text(l10n.continueTopicConversation),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
