import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/notifications/models/app_notification.dart';
import 'package:garbanzo_ai/core/widgets/skeleton.dart';
import 'package:garbanzo_ai/features/notifications/providers/notification_provider.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, provider, _) {
              if (provider.unreadCount == 0) return const SizedBox.shrink();
              return TextButton.icon(
                onPressed: provider.markAllRead,
                icon: const Icon(Icons.mark_email_read_outlined),
                label: const Text('Mark all read'),
              );
            },
          ),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.items.isEmpty) {
            return const SkeletonList(showAvatar: true);
          }
          if (provider.error != null && provider.items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(provider.error!, textAlign: TextAlign.center),
              ),
            );
          }
          if (provider.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No notifications yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: provider.refresh,
            child: ListView.separated(
              itemCount: provider.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final notification = provider.items[index];
                return _NotificationTile(
                  notification: notification,
                  onTap: () => provider.markRead(notification.id),
                  onDelete: () => provider.remove(notification.id),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    required this.onDelete,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey('notification-${notification.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: colorScheme.errorContainer,
        child: Icon(Icons.delete_outline, color: colorScheme.onErrorContainer),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _channelColor(colorScheme),
          child: Icon(_channelIcon(), color: colorScheme.onPrimary, size: 20),
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight: notification.isRead ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              notification.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(notification.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: notification.isRead
            ? null
            : Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
        onTap: onTap,
      ),
    );
  }

  IconData _channelIcon() {
    switch (notification.channel) {
      case 'reminders':
        return Icons.alarm;
      case 'system_alerts':
        return Icons.info_outline;
      case 'chat_responses':
      default:
        return Icons.chat_bubble_outline;
    }
  }

  Color _channelColor(ColorScheme colors) {
    switch (notification.channel) {
      case 'reminders':
        return colors.tertiary;
      case 'system_alerts':
        return colors.secondary;
      case 'chat_responses':
      default:
        return colors.primary;
    }
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${local.year}-${_two(local.month)}-${_two(local.day)}';
  }

  String _two(int n) => n.toString().padLeft(2, '0');
}
