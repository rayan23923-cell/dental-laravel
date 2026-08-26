import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/qr_image.dart';
import '../data/task_instance_repository.dart';
import '../domain/task_instance.dart';
import '../domain/task_instance_status.dart';
import 'status_badge.dart';
import 'task_instances_providers.dart';

class TaskInstanceDetailScreen extends ConsumerWidget {
  const TaskInstanceDetailScreen({super.key, required this.taskInstanceId});
  final int taskInstanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(taskInstanceDetailProvider(taskInstanceId));

    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل المهمة')),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : 'تعذر تحميل المهمة.'),
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

  Future<void> _setStatus(TaskInstanceStatus status) async {
    // Captured before the `await` so the catch block never touches
    // `context` itself post-async-gap.
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _updating = true);
    try {
      await ref.read(taskInstanceRepositoryProvider).updateStatus(widget.instance.id, status: status);
      invalidateTaskInstance(ref, widget.instance.id);
    } catch (e) {
      final message = e is ApiException ? e.userMessage : 'تعذر تحديث الحالة.';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final instance = widget.instance;
    final dateFormat = DateFormat('yyyy-MM-dd');

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
                  instance.task?.title ?? 'مهمة #${instance.taskId}',
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
              label: 'الطالب/الطبيب',
              value: instance.doctorUsername != null
                  ? '${instance.doctorName} (${instance.doctorUsername})'
                  : instance.doctorName!,
            ),
          if (instance.assignedByName != null) _InfoRow(label: 'بدأ بواسطة', value: instance.assignedByName!),
          if (instance.task?.departmentName != null) _InfoRow(label: 'القسم', value: instance.task!.departmentName!),
          if (instance.task?.caseSheetTypeNameAr != null)
            _InfoRow(label: 'نوع النموذج السريري', value: instance.task!.caseSheetTypeNameAr!),
          if (instance.assignedDate != null) _InfoRow(label: 'تاريخ الإسناد', value: dateFormat.format(instance.assignedDate!)),
          if (instance.completionDate != null) _InfoRow(label: 'تاريخ الإكمال', value: dateFormat.format(instance.completionDate!)),
          if (instance.grade != null) _InfoRow(label: 'الدرجة', value: instance.grade!.toStringAsFixed(2)),
          if (instance.notes != null && instance.notes!.isNotEmpty) _InfoRow(label: 'ملاحظات', value: instance.notes!),
          const SizedBox(height: 24),
          Text('تحديث الحالة', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final s in TaskInstanceStatus.values)
                ChoiceChip(
                  label: Text(s.arabicLabel),
                  selected: instance.status == s,
                  onSelected: _updating || instance.status == s ? null : (_) => _setStatus(s),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('رمز QR الخاص بهذه المهمة', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Center(child: QrImage(path: '/task-instances/${instance.id}/qr')),
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
