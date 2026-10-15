import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/notification_repository.dart';
import '../domain/app_notification.dart';
import 'notifications_providers.dart';

/// The notification inbox — reached from the bell icon on `HomeScreen`.
/// Today the only notification type is "a task was started for you"
/// (`App\Notifications\TaskAssigned`, `database` channel), so every entry
/// links to `/tasks/{taskInstanceId}` (the already-built
/// `TaskInstanceDetailScreen`) rather than needing per-type routing.
class NotificationInboxScreen extends ConsumerStatefulWidget {
  const NotificationInboxScreen({super.key});

  @override
  ConsumerState<NotificationInboxScreen> createState() => _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends ConsumerState<NotificationInboxScreen> {
  @override
  void initState() {
    super.initState();
    // `notificationsListProvider` is `autoDispose`, but `HomeScreen`'s own
    // bell badge keeps a listener on it alive for as long as `HomeScreen`
    // stays mounted underneath this pushed route (go_router doesn't dispose
    // it) — so without this, opening the inbox just re-served whatever was
    // already cached from whenever the badge last fetched, even if a new
    // notification arrived since. Confirmed live: started a real task,
    // opened the inbox, and it showed "لا توجد إشعارات" until this fix.
    // Scheduled post-frame since invalidating a provider during another
    // widget's `initState`/`build` isn't allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(notificationsListProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsListProvider);
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t['nav.notifications']!),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(notificationRepositoryProvider).markAllRead();
              ref.invalidate(notificationsListProvider);
            },
            child: Text(t['notifications.markAllRead']!),
          ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorView(
          error: error,
          onRetry: () => ref.invalidate(notificationsListProvider),
        ),
        data: (notifications) {
          // Wrapped in `RefreshIndicator` + a scrollable even when empty
          // (`AlwaysScrollableScrollPhysics`) — an earlier version only
          // wrapped the non-empty branch, so pull-to-refresh silently did
          // nothing on an empty inbox. Found live, not assumed.
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsListProvider),
            child: notifications.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 200),
                      Center(child: Text(t['notifications.empty']!)),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _NotificationTile(notification: notifications[i]),
                  ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});
  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Card(
      color: notification.isUnread ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
      child: ListTile(
        leading: notification.isUnread
            ? const CircleAvatar(radius: 5, backgroundColor: Colors.blue)
            : const SizedBox(width: 10),
        title: Text(
          notification.title,
          style: TextStyle(fontWeight: notification.isUnread ? FontWeight.bold : FontWeight.normal),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.message),
            const SizedBox(height: 4),
            Text(dateFormat.format(notification.createdAt), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        onTap: () async {
          if (notification.isUnread) {
            await ref.read(notificationRepositoryProvider).markRead(notification.id);
            ref.invalidate(notificationsListProvider);
          }
          if (!context.mounted) return;
          // Opens what it is about (2026-10-15, as on the web): the case, or
          // the start requests (staff) / my tasks (doctor).
          if (notification.taskInstanceId != null) {
            context.push('/tasks/${notification.taskInstanceId}');
          } else if (notification.type == 'task_start_request') {
            context.go(notification.kind == 'new' ? '/admin/task-progress?tab=requests' : '/home');
          }
        },
      ),
    );
  }
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final message = error is ApiException ? (error as ApiException).userMessage : t['common.unexpectedError']!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(t['common.retry']!)),
        ],
      ),
    );
  }
}
