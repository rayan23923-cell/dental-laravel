import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';
import '../domain/app_notification.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(apiClientProvider));
});

/// Talks to `Api\NotificationController` — the current principal's own
/// notifications (Doctor or User), scoped server-side.
class NotificationRepository {
  NotificationRepository(this._client);
  final ApiClient _client;

  Future<Paginated<AppNotification>> list() async {
    final data = await _client.getJson('/notifications') as Map<String, dynamic>;
    return Paginated.fromJson(data, AppNotification.fromJson);
  }

  Future<void> markRead(String id) {
    return _client.postJson('/notifications/$id/read');
  }

  Future<void> markAllRead() {
    return _client.postJson('/notifications/read-all');
  }
}
