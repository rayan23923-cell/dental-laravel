import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/qr_dialog.dart';
import '../domain/pending_task.dart';
import 'task_instances_providers.dart';

/// "رموز المهام المعلقة" (by request, 2026-09-01) — a dedicated screen
/// listing every task type in the doctor's own stage they have no
/// instance of at all yet, each showing the same "pending_task" QR a
/// senior/admin scans to start it for them. Flutter port of the web's own
/// `resources/js/Pages/Doctor/PendingTasksQr.vue` (reached from
/// `DoctorLayout.vue`'s own nav) — same card content (title, department,
/// required count, grade, notes), same "اعرض هذا الرمز على المشرف لبدء
/// المهمة" caption in the QR dialog. The per-row QR button already inline
/// in `MyTasksScreen` covers the same *data*, but this dedicated grid
/// (one card per pending task *type*, not interleaved with in-progress/
/// completed slots) is what the web's own nav links to, so it gets a
/// standing screen here too rather than staying web-only.
class PendingTasksQrScreen extends ConsumerWidget {
  const PendingTasksQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(pendingTasksQrProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('رموز المهام المعلقة')),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is ApiException
                    ? error.userMessage
                    : 'حدث خطأ غير متوقع.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(pendingTasksQrProvider),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
        data: (tasks) => _PendingTasksBody(tasks: tasks),
      ),
    );
  }
}

class _PendingTasksBody extends StatelessWidget {
  const _PendingTasksBody({required this.tasks});
  final List<PendingTask> tasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          sliver: SliverToBoxAdapter(
            child: Text(
              'المهام التي لم تبدأ بها بعد في مرحلتك. اعرض رمز المهمة ليمسحه المشرف ويبدأها لك.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
        ),
        if (tasks.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text('لا توجد مهام معلقة — بدأت جميع مهام مرحلتك.'),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.separated(
              itemCount: tasks.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _PendingTaskCard(task: tasks[index]),
            ),
          ),
      ],
    );
  }
}

class _PendingTaskCard extends StatelessWidget {
  const _PendingTaskCard({required this.task});
  final PendingTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'القسم: ${task.department ?? '—'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(
                  label: Text('المطلوب: ${task.requiredCount}'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                if (task.grade != null)
                  Chip(
                    label: Text('الدرجة: ${task.grade}'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            if (task.notes != null && task.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(task.notes!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.qr_code_2),
                label: const Text('رمز QR'),
                onPressed: () => showQrDialog(
                  context,
                  imagePath: '/pending-tasks/${task.id}/qr',
                  title: 'رمز المهمة المعلقة',
                  caption:
                      'اعرض هذا الرمز على المشرف لبدء المهمة وتخصيص حالة لك.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
