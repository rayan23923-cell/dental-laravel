import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/qr_dialog.dart';
import '../../case_sheet_forms/data/case_sheet_record_repository.dart';
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
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['nav.pendingTasksQr']!)),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is ApiException
                    ? error.userMessage
                    : t['common.unexpectedError']!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(pendingTasksQrProvider),
                child: Text(t['common.retry']!),
              ),
            ],
          ),
        ),
        data: (tasks) => _PendingTasksBody(tasks: tasks),
      ),
    );
  }
}

class _PendingTasksBody extends ConsumerWidget {
  const _PendingTasksBody({required this.tasks});
  final List<PendingTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          sliver: SliverToBoxAdapter(
            child: Text(
              t['tasksQr.pendingIntro']!,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
        ),
        if (tasks.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(t['tasksQr.pendingEmpty']!),
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

class _PendingTaskCard extends ConsumerStatefulWidget {
  const _PendingTaskCard({required this.task});
  final PendingTask task;

  @override
  ConsumerState<_PendingTaskCard> createState() => _PendingTaskCardState();
}

class _PendingTaskCardState extends ConsumerState<_PendingTaskCard> {
  PendingTask get task => widget.task;
  bool _openingCaseSheet = false;

  /// Same pre-instance draft as `MyTasksScreen`'s own
  /// `_openCaseSheetForTask()` (`Api\CaseSheetController::openForTask()`) —
  /// lets the doctor start filling the sheet before the task is even
  /// assigned, without needing the QR-scan/screening flow this screen's own
  /// QR button still triggers.
  Future<void> _openCaseSheetForTask() async {
    setState(() => _openingCaseSheet = true);
    try {
      final result = await ref.read(caseSheetRecordRepositoryProvider).openForTask(task.id);
      if (!mounted) return;
      final query = '?task_id=${task.id}';
      context.push(
        result.recordId != null
            ? '/case-sheets/${result.resource}/${result.recordId}$query'
            : '/case-sheets/${result.resource}/new$query',
      );
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['tasksQr.openCaseSheetFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _openingCaseSheet = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider);

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
              '${t['labels.department']!}: ${task.department ?? '—'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(
                  label: Text('${t['labels.required']!}: ${task.requiredCount}'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                if (task.grade != null)
                  Chip(
                    label: Text('${t['labels.grade']!}: ${task.grade}'),
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
            Row(
              children: [
                Expanded(
                  child: _openingCaseSheet
                      ? const Center(
                          child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : OutlinedButton.icon(
                          icon: const Icon(Icons.description_outlined),
                          label: Text(t['labels.openCaseSheet']!),
                          onPressed: _openCaseSheetForTask,
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.qr_code_2),
                    label: Text(t['labels.qrCode']!),
                    onPressed: () => showQrDialog(
                      context,
                      imagePath: '/pending-tasks/${task.id}/qr',
                      title: t['tasksQr.qrTitle']!,
                      caption: t['tasksQr.qrCaption']!,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
