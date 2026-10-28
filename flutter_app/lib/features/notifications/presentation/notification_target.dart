import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/notification_repository.dart';
import '../domain/app_notification.dart';
import 'notifications_providers.dart';

/// Where a notification leads (2026-10-15, as on the web): the case, or the
/// start requests (staff) / my tasks (doctor). Null when it is about nothing
/// to open. Shared by the inbox, the in-app alert and a tapped push
/// (2026-10-28, by request: "الإشعار يفتح الشاشة المعنية مباشرة").
String? notificationRoute({int? taskInstanceId, String? type, String? kind}) {
  if (taskInstanceId != null) return '/tasks/$taskInstanceId';
  if (type == 'task_start_request') return kind == 'new' ? '/admin/task-progress?tab=requests' : '/home';
  return null;
}

/// The case opens on top; the other targets are shell screens, switched to.
void openNotificationRoute(GoRouter router, String route) =>
    route.startsWith('/tasks/') ? router.push(route) : router.go(route);

/// Marks [notification] read and opens what it is about; false when there
/// is nothing to open.
Future<bool> openNotification(BuildContext context, WidgetRef ref, AppNotification notification) async {
  final router = GoRouter.of(context);
  if (notification.isUnread) {
    try {
      await ref.read(notificationRepositoryProvider).markRead(notification.id);
    } catch (_) {
      // Still opens; it stays unread until the next try.
    }
    ref.invalidate(notificationsListProvider);
  }
  final route = notificationRoute(
    taskInstanceId: notification.taskInstanceId,
    type: notification.type,
    kind: notification.kind,
  );
  if (route == null) return false;
  openNotificationRoute(router, route);
  return true;
}
