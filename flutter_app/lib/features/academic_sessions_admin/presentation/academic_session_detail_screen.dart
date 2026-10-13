import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../data/academic_sessions_repository.dart';
import '../domain/academic_session_admin.dart';
import 'academic_sessions_providers.dart';

class AcademicSessionDetailScreen extends ConsumerWidget {
  const AcademicSessionDetailScreen({super.key, required this.sessionId});
  final int sessionId;

  Future<void> _setCurrent(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(academicSessionsRepositoryProvider).setCurrent(sessionId);
      ref.invalidate(academicSessionDetailProvider(sessionId));
      ref.invalidate(academicSessionListProvider);
      ref.invalidate(currentAcademicYearProvider);
      if (context.mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['academicSessionsAdmin.becameCurrentSuccess']!)));
      }
    } catch (e) {
      if (context.mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['academicSessionsAdmin.setCurrentFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, AcademicSessionAdmin session) async {
    final t = ref.read(translationsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t['academicSessionsAdmin.deleteTitle']!),
        content: Text(trf(t['academicSessionsAdmin.deleteConfirmBody']!, {'name': session.name})),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t['taxonomyAdmin.cancel']!)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t['taxonomyAdmin.deleteTitlePrefix']!)),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(academicSessionsRepositoryProvider).delete(sessionId);
      ref.invalidate(academicSessionListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['academicSessionsAdmin.deletedSuccess']!)));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        final message = e is ApiException ? e.userMessage : t['academicSessionsAdmin.deleteFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(academicSessionDetailProvider(sessionId));
    final t = ref.watch(translationsProvider);

    return detailAsync.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(error is ApiException ? error.userMessage : t['academicSessionsAdmin.loadFailed']!)),
      ),
      data: (detail) {
        final session = detail.session;
        final stats = detail.stats;
        return Scaffold(
          appBar: AppBar(
            title: Text(session.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => context.push('/admin/academic-sessions/$sessionId/edit'),
              ),
              if (!session.isCurrent)
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, ref, session)),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Forced LTR — see permission_edit_screen.dart's module-count
              // comment for why two LTR-ish values joined by a neutral
              // separator get reordered inside RTL text otherwise.
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text('${session.startDate} → ${session.endDate}', style: Theme.of(context).textTheme.bodyMedium),
              ),
              const SizedBox(height: 8),
              // Same exclusive-toggle switch as academic_session_list_screen.dart's
              // `_SessionTile` — see its doc comment for why turning this
              // on alone is enough (the backend hook clears every other
              // year's `is_current`) and why there's no "turn off" case.
              Row(
                children: [
                  Text(t['academicSessionsAdmin.currentLabel']!),
                  const Spacer(),
                  CupertinoSwitch(
                    value: session.isCurrent,
                    onChanged: session.isCurrent ? null : (_) => _setCurrent(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(t['academicSessionsAdmin.statisticsHeading']!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    _StatRow(label: t['academicSessionsAdmin.doctorsStat']!, value: stats.doctors),
                    if (ref.watch(groupsEnabledProvider))
                      _StatRow(label: t['academicSessionsAdmin.groupsStat']!, value: stats.groups),
                    _StatRow(label: t['academicSessionsAdmin.requiredTasksStat']!, value: stats.requiredTasks),
                    _StatRow(label: t['academicSessionsAdmin.doneTasksStat']!, value: stats.doneTasks),
                    _StatRow(label: t['academicSessionsAdmin.remainingTasksStat']!, value: stats.remainingTasks),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text('$value', style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
