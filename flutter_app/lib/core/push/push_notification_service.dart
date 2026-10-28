import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../router/app_router.dart';
import '../../features/notifications/presentation/notification_target.dart';
import '../../features/notifications/presentation/notifications_providers.dart';

/// Registers this device for push notifications (task-started alerts) and
/// keeps the token in sync with the backend — best-effort throughout, since
/// no real Firebase project exists yet (see README.md's Firebase section).
/// Every step here no-ops safely rather than throwing when Firebase isn't
/// actually configured, so calling `init()` is always safe regardless of
/// whether push is live.
class PushNotificationService {
  PushNotificationService(this._ref);
  final Ref _ref;

  Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (Firebase.apps.isEmpty) return; // Not configured yet — see main.dart.

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      final token = await messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }

      messaging.onTokenRefresh.listen(_registerToken);

      // A live push while the app is open just refreshes the existing
      // in-app inbox/badge (Part 2) rather than needing a second, separate
      // foreground-banner UI — background/terminated notifications already
      // show via the OS system tray automatically once FCM is configured,
      // since `PushNotifier` sends a `notification` payload block.
      FirebaseMessaging.onMessage.listen((_) {
        _ref.invalidate(notificationsListProvider);
      });

      // A tapped push opens what it is about (2026-10-28, by request), from
      // the background or from a closed app (after the session restores).
      FirebaseMessaging.onMessageOpenedApp.listen(_open);
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        Future.delayed(const Duration(milliseconds: 800), () => _open(initial));
      }
    } catch (_) {
      // Fail-open — push is a nice-to-have, never block the app on it.
    }
  }

  void _open(RemoteMessage message) {
    final data = message.data;
    final route = notificationRoute(
      taskInstanceId: int.tryParse('${data['task_instance_id'] ?? ''}'),
      // The decline push carries only the request's id.
      type: data.containsKey('task_start_request_id') ? 'task_start_request' : null,
    );
    _ref.invalidate(notificationsListProvider);
    openNotificationRoute(_ref.read(routerProvider), route ?? '/notifications');
  }

  Future<void> _registerToken(String token) async {
    try {
      await _ref.read(apiClientProvider).postJson('/device-tokens', body: {
        'token': token,
        'platform': 'android',
      });
    } catch (_) {
      // Best-effort — a failed registration just means no push to this
      // device until the next successful retry (next login/token refresh).
    }
  }
}
