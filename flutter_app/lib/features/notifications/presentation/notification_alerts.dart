import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import 'notifications_providers.dart';

/// New-notification alerts while the app is open (2026-10-14, by request):
/// checks the inbox every 20 seconds and when the app comes back to the
/// front, and for each new unread notification (a task start request, or
/// its approval or turn-down) plays a chime and shows it in a snack bar.
/// Background pushes still need Firebase (see `PushNotificationService`).
class NotificationAlerts extends ConsumerStatefulWidget {
  const NotificationAlerts({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<NotificationAlerts> createState() => _NotificationAlertsState();
}

class _NotificationAlertsState extends ConsumerState<NotificationAlerts> with WidgetsBindingObserver {
  Timer? _timer;
  Set<String>? _seen;
  final _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (mounted) ref.invalidate(notificationsListProvider);
  }

  Future<void> _chime() async {
    try {
      await _player.play(AssetSource('sounds/notify.wav'));
    } catch (_) {
      // No audio — the snack bar still shows.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(notificationsListProvider, (_, next) {
      final items = next.valueOrNull;
      if (items == null) return;
      final fresh = _seen == null ? const [] : items.where((n) => n.isUnread && !_seen!.contains(n.id)).toList();
      _seen = items.map((n) => n.id).toSet();
      if (fresh.isEmpty) return;

      _chime();
      final t = ref.read(translationsProvider);
      final first = fresh.first;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
            content: Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(first.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (first.message.isNotEmpty) Text(first.message),
                    ],
                  ),
                ),
              ],
            ),
            action: SnackBarAction(label: t['notifications.view']!, onPressed: () => context.push('/notifications')),
          ),
        );
    });
    return widget.child;
  }
}
