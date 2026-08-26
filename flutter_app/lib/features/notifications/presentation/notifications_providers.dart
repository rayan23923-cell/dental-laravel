import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notification_repository.dart';
import '../domain/app_notification.dart';

/// First page of the current principal's notifications, newest first.
final notificationsListProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final page = await ref.watch(notificationRepositoryProvider).list();
  return page.items;
});

/// Unread count for the home-screen bell badge — derived from the same
/// first-page fetch above rather than a dedicated count endpoint (a small
/// teaching clinic's notification volume doesn't need exact-beyond-one-page
/// accuracy for a badge number).
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notifications = ref.watch(notificationsListProvider).valueOrNull ?? const [];
  return notifications.where((n) => n.isUnread).length;
});
