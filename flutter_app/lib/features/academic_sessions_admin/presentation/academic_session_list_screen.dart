import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/academic_sessions_repository.dart';
import '../domain/academic_session_admin.dart';
import 'academic_sessions_providers.dart';

class AcademicSessionListScreen extends ConsumerWidget {
  const AcademicSessionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(academicSessionListProvider);
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['academicSessionsAdmin.title']!)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/admin/academic-sessions/new'),
        child: const Icon(Icons.add),
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : t['academicSessionsAdmin.loadFailed']!),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return Center(child: Text(t['academicSessionsAdmin.emptyList']!));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(academicSessionListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: sessions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _SessionTile(session: sessions[i]),
            ),
          );
        },
      ),
    );
  }
}

class _SessionTile extends ConsumerStatefulWidget {
  const _SessionTile({required this.session});
  final AcademicSessionAdmin session;

  @override
  ConsumerState<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends ConsumerState<_SessionTile> {
  bool _submitting = false;

  /// Turning this year's switch on makes it the active one — the backend's
  /// `AcademicSession::booted()` `saving()` hook (see `dental_laravel/
  /// README.md`) already guarantees every other row's `is_current` gets
  /// cleared in the same request, so this call alone is enough; no
  /// separate "turn off the others" step needed here. There's no
  /// corresponding "turn off" action — exactly one year must always be
  /// active, so switching off only ever happens by switching a *different*
  /// row on (that row's switch is left disabled below while it's already
  /// current, same reasoning `academic_session_detail_screen.dart`'s
  /// "اجعله العام الدراسي النشط" button already used before this replaced it).
  Future<void> _setCurrent() async {
    setState(() => _submitting = true);
    try {
      await ref.read(academicSessionsRepositoryProvider).setCurrent(widget.session.id);
      ref.invalidate(academicSessionListProvider);
      ref.invalidate(currentAcademicYearProvider);
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['academicSessionsAdmin.setCurrentFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final t = ref.watch(translationsProvider);

    return Card(
      child: ListTile(
        title: Text(session.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Forced LTR: two dates joined only by "→" have no strong-
            // direction anchor inside RTL text, so the bidi algorithm
            // reorders them — confirmed live showing end before start.
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text('${session.startDate} → ${session.endDate}'),
            ),
            Text(trf(t['academicSessionsAdmin.groupsAndTasksCount']!, {'groups': session.groupsCount, 'tasks': session.tasksCount})),
          ],
        ),
        isThreeLine: true,
        trailing: _submitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : CupertinoSwitch(
                value: session.isCurrent,
                onChanged: session.isCurrent ? null : (_) => _setCurrent(),
              ),
        onTap: () => context.push('/admin/academic-sessions/${session.id}'),
      ),
    );
  }
}
