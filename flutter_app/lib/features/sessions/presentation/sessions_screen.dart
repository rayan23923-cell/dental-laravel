import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../data/sessions_repository.dart';
import '../domain/account_session.dart';
import 'sessions_providers.dart';

/// Instagram-style "الأجهزة النشطة" — every device/app install this
/// account is currently logged in from, reached from `ProfileScreen`.
/// Mirrors the web app's `ActiveSessionsPanel.vue`, backed by the same
/// `Api\SessionController` endpoints.
class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(accountSessionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الأجهزة النشطة')),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: Text('لا توجد أجهزة أخرى مسجّلة الدخول حاليًا.')),
                )
              else
                ...sessions.map((s) => _SessionTile(session: s)),
              if (sessions.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _logoutAll(context, ref),
                  icon: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
                  label: Text(
                    'تسجيل الخروج من جميع الأجهزة',
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج من جميع الأجهزة'),
        content: const Text('سيتم تسجيل الخروج من جميع الأجهزة المسجّل الدخول منها بهذا الحساب. متابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('تسجيل الخروج', style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
        final message = e is ApiException ? e.userMessage : 'تعذر تسجيل الخروج من جميع الأجهزة.';
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إنهاء الجلسة'),
        content: Text('إنهاء الجلسة على "${widget.session.deviceName}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('إنهاء', style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
        final message = e is ApiException ? e.userMessage : 'تعذر إنهاء الجلسة.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        setState(() => _ending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final lastActive = session.lastUsedAt != null ? dateFormat.format(session.lastUsedAt!) : 'لم يُستخدم بعد';

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
                child: Text('هذا الجهاز', style: Theme.of(context).textTheme.labelSmall),
              ),
            ],
          ],
        ),
        subtitle: Text('${session.location ?? 'الموقع غير معروف'} · آخر نشاط: $lastActive'),
        trailing: session.isCurrent
            ? null
            : _ending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(onPressed: _end, child: const Text('إنهاء')),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is ApiException ? (error as ApiException).userMessage : 'حدث خطأ غير متوقع.';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}
