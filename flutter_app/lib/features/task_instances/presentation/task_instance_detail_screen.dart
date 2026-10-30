import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/qr_dialog.dart';
import '../../case_sheet_forms/data/case_sheet_record_repository.dart';
import '../data/task_instance_repository.dart';
import '../domain/task_instance.dart';
import '../domain/task_instance_status.dart';
import 'status_badge.dart';
import 'task_instances_providers.dart';
import '../../../core/widgets/tg_spinner.dart';

class TaskInstanceDetailScreen extends ConsumerWidget {
  const TaskInstanceDetailScreen({super.key, required this.taskInstanceId});
  final int taskInstanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(taskInstanceDetailProvider(taskInstanceId));
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['taskDetail.title']!)),
      body: detailAsync.when(
        loading: () => const Center(child: TgSpinner()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : t['taskDetail.loadFailed']!),
        ),
        data: (instance) => _DetailBody(instance: instance),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.instance});
  final TaskInstance instance;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  bool _updating = false;
  bool _openingCaseSheet = false;

  /// Mirrors the web's `CaseSheetController::open()` — reuse the sheet
  /// already filled for this case if there is one, otherwise a blank sheet
  /// pre-linked to it. Added 2026-08-27: this screen previously had no
  /// entry point into the case-sheet feature at all.
  Future<void> _openCaseSheet() async {
    setState(() => _openingCaseSheet = true);
    try {
      final result = await ref.read(caseSheetRecordRepositoryProvider).openFor(widget.instance.id);
      if (!mounted) return;
      if (result.recordId != null) {
        context.push('/case-sheets/${result.resource}/${result.recordId}?task_instances_id=${widget.instance.id}');
      } else {
        context.push('/case-sheets/${result.resource}/new?task_instances_id=${widget.instance.id}');
      }
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['myTasks.openFormFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _openingCaseSheet = false);
    }
  }

  Future<void> _setStatus(TaskInstanceStatus status) async {
    // Captured before the `await` so the catch block never touches
    // `context` itself post-async-gap.
    final messenger = ScaffoldMessenger.of(context);
    final t = ref.read(translationsProvider);

    setState(() => _updating = true);
    try {
      await ref.read(taskInstanceRepositoryProvider).updateStatus(widget.instance.id, status: status);
      invalidateTaskInstance(ref, widget.instance.id);
    } catch (e) {
      final message = e is ApiException ? e.userMessage : t['taskDetail.updateStatusFailed']!;
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final instance = widget.instance;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final t = ref.watch(translationsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  instance.task?.title ?? trf(t['taskDetail.taskFallback']!, {'id': instance.taskId}),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              StatusBadge(status: instance.status),
            ],
          ),
          const SizedBox(height: 16),
          // Omitted (not just blank) unless the server actually sent
          // `doctor`/`assigned_by_name` — it only does that for the owning
          // doctor or a staff user who is admin or holds
          // `task_progress,view` (see `App\Support\TaskInstanceVisibility`
          // server-side). A staff viewer without that permission never
          // receives this data in the first place, so there is nothing to
          // hide here beyond just not rendering a null.
          if (instance.doctorName != null)
            _InfoRow(
              label: t['taskDetail.doctorLabel']!,
              value: instance.doctorUsername != null
                  ? '${instance.doctorName} (${instance.doctorUsername})'
                  : instance.doctorName!,
            ),
          if (instance.assignedByName != null) _InfoRow(label: t['taskDetail.assignedByLabel']!, value: instance.assignedByName!),
          if (instance.task?.departmentName != null) _InfoRow(label: t['labels.department']!, value: instance.task!.departmentName!),
          if (instance.task?.caseSheetTypeNameAr != null)
            _InfoRow(label: t['taskDetail.caseSheetTypeLabel']!, value: instance.task!.caseSheetTypeNameAr!),
          if (instance.assignedDate != null) _InfoRow(label: t['taskDetail.assignedDateLabel']!, value: dateFormat.format(instance.assignedDate!)),
          if (instance.completionDate != null) _InfoRow(label: t['taskDetail.completionDateLabel']!, value: dateFormat.format(instance.completionDate!)),
          if (instance.grade != null) _InfoRow(label: t['labels.grade']!, value: instance.grade!.toStringAsFixed(2)),
          if (instance.notes != null && instance.notes!.isNotEmpty) _InfoRow(label: t['taskDetail.notesLabel']!, value: instance.notes!),
          const SizedBox(height: 24),
          Text(t['taskDetail.updateStatusHeading']!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final s in TaskInstanceStatus.values)
                ChoiceChip(
                  label: Text(s.label(t)),
                  selected: instance.status == s,
                  onSelected: _updating || instance.status == s ? null : (_) => _setStatus(s),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openingCaseSheet ? null : _openCaseSheet,
            icon: _openingCaseSheet
                ? const SizedBox(height: 16, width: 16, child: TgSpinner(strokeWidth: 2))
                : const Icon(Icons.description_outlined),
            label: Text(t['labels.caseSheetForm']!),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showQrDialog(
              context,
              imagePath: '/task-instances/${instance.id}/qr',
              title: t['myTasks.qrCaseTitle']!,
              caption: t['myTasks.qrCaseCaption']!,
            ),
            icon: const Icon(Icons.qr_code_2),
            label: Text(t['taskDetail.qrButtonLabel']!),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
