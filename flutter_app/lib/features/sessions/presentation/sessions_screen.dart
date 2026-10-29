import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/sessions_repository.dart';
import '../domain/account_session.dart';
import 'sessions_providers.dart';
import '../../../core/widgets/tg_spinner.dart';

/// Instagram-style "الأجهزة النشطة" — every device/app install this
/// account is currently logged in from, reached from `ProfileScreen`.
/// Mirrors the web app's `ActiveSessionsPanel.vue`, backed by the same
/// `Api\SessionController` endpoints.
class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(accountSessionsProvider);
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['profile.activeSessions']!)),
      body: sessionsAsync.when(
        loading: () => const Center(child: TgSpinner()),
        error: (error, stackTrace) => _ErrorView(
          error: error,
          onRetry: () => ref.invalidate(accountSessionsProvider),
        ),
        data: (sessions) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(accountSessionsProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            children: [
              if (sessions.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Center(child: Text(t['sessions.empty']!)),
                )
              else
                ...sessions.map((s) => _SessionTile(session: s)),
              if (sessions.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _logoutAll(context, ref),
                  icon: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
                  label: Text(
                    t['sessions.logoutAll']!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logoutAll(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t['sessions.logoutAll']!),
        content: Text(t['sessions.logoutAllConfirm']!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t['nav.cancel']!)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t['nav.logout']!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(sessionsRepositoryProvider).logoutAll();
      ref.invalidate(accountSessionsProvider);
    } catch (e) {
      if (context.mounted) {
        final message = e is ApiException ? e.userMessage : t['sessions.logoutAllFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
}

IconData _deviceIcon(String type) => switch (type) {
      'android' => Icons.phone_android,
      'ios' => Icons.phone_iphone,
      'windows' => Icons.desktop_windows,
      'macos' => Icons.laptop_mac,
      'linux' => Icons.terminal,
      'web' => Icons.language,
      _ => Icons.devices_other,
    };

class _SessionTile extends ConsumerStatefulWidget {
  const _SessionTile({required this.session});
  final AccountSession session;

  @override
  ConsumerState<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends ConsumerState<_SessionTile> {
  bool _ending = false;

  Future<void> _end() async {
    final t = ref.read(translationsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t['sessions.endSessionTitle']!),
        content: Text(trf(t['sessions.endConfirm']!, {'device': widget.session.deviceName})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t['nav.cancel']!)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t['sessions.end']!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _ending = true);
    try {
      await ref.read(sessionsRepositoryProvider).end(widget.session.id);
      ref.invalidate(accountSessionsProvider);
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['sessions.endFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        setState(() => _ending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final t = ref.watch(translationsProvider);
    final lastActive = session.lastUsedAt != null ? dateFormat.format(session.lastUsedAt!) : t['sessions.neverUsed']!;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Icon(_deviceIcon(session.deviceType))),
        title: Row(
          children: [
            Flexible(child: Text(session.deviceName, overflow: TextOverflow.ellipsis)),
            if (session.isCurrent) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(t['sessions.thisDevice']!, style: Theme.of(context).textTheme.labelSmall),
              ),
            ],
          ],
        ),
        subtitle: Text('${session.location ?? t['sessions.unknownLocation']!} · ${t['sessions.lastActive']!}: $lastActive'),
        trailing: session.isCurrent
            ? null
            : _ending
                ? const SizedBox(width: 20, height: 20, child: TgSpinner(strokeWidth: 2))
                : TextButton(onPressed: _end, child: Text(t['sessions.end']!)),
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
