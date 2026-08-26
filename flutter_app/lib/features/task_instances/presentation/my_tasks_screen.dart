import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../task_progress_admin/domain/task_progress_group.dart';
import '../domain/my_task_department.dart';
import 'task_instances_providers.dart';

/// "مهامي" — the doctor's own tasks, grouped by department and, within a
/// department, by task (one `ExpansionTile` per task showing "X/N مكتملة",
/// expanding to the individual required slots) — matching the original
/// PHP app's `doctor/required_tasks.php` (department grouping, N slots per
/// task) combined with the admin screen's collapse/expand interaction
/// (`admin/ajax/get_group_doctors.php`), per the user's own description.
///
/// Data comes from `GET /my-task-progress`
/// (`Api\TaskProgressController::mine()`/`App\Services\DoctorTaskSummary`)
/// rather than the flat `GET /my-task-instances` this screen replaces —
/// the flat endpoint only returns rows that already exist in
/// `task_instances`, so it can't show a required-but-not-yet-started slot
/// at all. Status filtering (the old screen's chip row) is dropped: each
/// slot already shows its own status badge in this grouped view.
class MyTasksScreen extends ConsumerStatefulWidget {
  const MyTasksScreen({super.key});

  @override
  ConsumerState<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends ConsumerState<MyTasksScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  int _departmentCount = -1;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _ensureTabController(int departmentCount) {
    if (_departmentCount == departmentCount) return;
    _departmentCount = departmentCount;
    _tabController?.dispose();
    _tabController = departmentCount > 0 ? TabController(length: departmentCount, vsync: this) : null;
  }

  @override
  Widget build(BuildContext context) {
    final departmentsAsync = ref.watch(myTaskProgressProvider);

    return departmentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _ErrorView(
        error: error,
        onRetry: () => ref.invalidate(myTaskProgressProvider),
      ),
      data: (departments) {
        _ensureTabController(departments.length);

        if (departments.isEmpty) {
          return const Center(child: Text('لا توجد أقسام لمرحلتك.'));
        }

        return Column(
          children: [
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: [for (final d in departments) Tab(text: d.name)],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [for (final d in departments) _DepartmentTaskList(department: d)],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DepartmentTaskList extends StatelessWidget {
  const _DepartmentTaskList({required this.department});
  final MyTaskDepartment department;

  @override
  Widget build(BuildContext context) {
    final tasks = department.doctor.tasks;
    if (tasks.isEmpty) {
      return const Center(child: Text('لا توجد مهام في هذا القسم.'));
    }

    // Group this department's slot cards by task_id, preserving the
    // backend's own task ordering (grouped by title) — a `Map` insertion
    // order is stable in Dart, so no extra sort needed.
    final byTask = <int, List<TaskSlotCard>>{};
    for (final card in tasks) {
      byTask.putIfAbsent(card.taskId, () => []).add(card);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final entry in byTask.entries) _TaskGroupTile(slots: entry.value),
      ],
    );
  }
}

class _TaskGroupTile extends StatelessWidget {
  const _TaskGroupTile({required this.slots});
  final List<TaskSlotCard> slots;

  @override
  Widget build(BuildContext context) {
    final title = slots.first.taskTitle;
    final completed = slots.where((s) => s.status == 'completed').length;
    final required = slots.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(title),
        subtitle: Text('$completed/$required مكتملة'),
        children: [for (final slot in slots) _SlotRow(slot: slot)],
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot});
  final TaskSlotCard slot;

  Color _statusColor(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return switch (slot.status) {
      'completed' => Colors.green,
      'assigned' => colors.primary,
      'pending' => Colors.orange,
      _ => colors.outline,
    };
  }

  String _statusLabel() => switch (slot.status) {
        'completed' => 'مكتملة',
        'assigned' => 'قيد التنفيذ',
        'pending' => 'معلّقة',
        _ => 'لم تبدأ بعد',
      };

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final date = slot.completionDate ?? slot.assignedDate;
    final parsedDate = date != null ? DateTime.tryParse(date) : null;

    return ListTile(
      title: Text('الحالة ${slot.slot}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor(context).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel(),
                  style: TextStyle(color: _statusColor(context), fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
              if (slot.grade != null) ...[
                const SizedBox(width: 8),
                Text('الدرجة: ${slot.grade}'),
              ],
            ],
          ),
          if (parsedDate != null) Text(dateFormat.format(parsedDate)),
          if (slot.notes != null && slot.notes!.isNotEmpty) Text(slot.notes!),
        ],
      ),
      // Only a started slot (has a real instance) has anything to open —
      // an unassigned slot is purely informational.
      trailing: slot.instanceId != null ? const Icon(Icons.chevron_left) : null,
      onTap: slot.instanceId != null ? () => context.push('/tasks/${slot.instanceId}') : null,
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
