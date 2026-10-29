import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../domain/doctor_progress.dart';
import 'task_progress_providers.dart';
import '../../../core/widgets/tg_spinner.dart';

/// One doctor's task progress — what a doctor's ID card QR opens from the
/// task-progress scanner, like the web's `Doctors/Progress.vue` (read-only
/// here; grading stays on the task progress matrix).
class DoctorProgressScreen extends ConsumerWidget {
  const DoctorProgressScreen({super.key, required this.doctorId});

  final int doctorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final progressAsync = ref.watch(doctorProgressProvider(doctorId));

    return Scaffold(
      appBar: AppBar(
        title: Text(progressAsync.valueOrNull?.name ?? t['doctorProgress.title']!),
      ),
      body: progressAsync.when(
        loading: () => const Center(child: TgSpinner()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error is ApiException ? error.userMessage : t['doctorProgress.loadFailed']!,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (progress) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(doctorProgressProvider(doctorId)),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _Header(progress: progress),
              const SizedBox(height: 12),
              if (progress.tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(t['doctorProgress.empty']!, textAlign: TextAlign.center),
                )
              else
                for (final task in progress.tasks) _TaskRow(task: task),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.progress});
  final DoctorProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final details = [
      if (progress.username.isNotEmpty) progress.username,
      if (progress.educationType != null) progress.educationType!,
      if (progress.stage != null) progress.stage!,
      if (progress.group != null) progress.group!,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(progress.name, style: Theme.of(context).textTheme.titleMedium),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(details.join(' · '), style: const TextStyle(color: Colors.grey)),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Stat(label: t['doctorProgress.total']!, value: progress.total, color: Colors.indigo),
                _Stat(label: t['doctorProgress.completed']!, value: progress.completed, color: Colors.green),
                _Stat(label: t['doctorProgress.inProgress']!, value: progress.assigned, color: Colors.orange),
                _Stat(label: t['doctorProgress.pending']!, value: progress.pending, color: Colors.blueGrey),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide.none,
      label: Text('$label: $value', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task});
  final DoctorProgressTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final ratio = task.requiredCount > 0 ? (task.completed / task.requiredCount).clamp(0.0, 1.0) : 0.0;
    final done = task.requiredCount > 0 && task.completed >= task.requiredCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(
                  trf(t['doctorProgress.completedOf']!, {'done': task.completed, 'required': task.requiredCount}),
                  style: TextStyle(color: done ? Colors.green : null),
                ),
              ],
            ),
            if (task.department != null) ...[
              const SizedBox(height: 2),
              Text(task.department!, style: const TextStyle(color: Colors.grey)),
            ],
            const SizedBox(height: 8),
            LinearProgressIndicator(value: ratio, color: done ? Colors.green : null),
          ],
        ),
      ),
    );
  }
}
