import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/academic_year_banner.dart';
import '../../../core/widgets/cascading_dropdown.dart';
import '../domain/task_admin.dart';
import 'tasks_admin_providers.dart';

/// "المهام" — mirrors dental_clinics2/admin/manage_tasks.php: three
/// cascading dropdowns (نوع الدراسة -> المرحلة -> القسم), and the task
/// list is hidden entirely — not just narrowed — until a stage AND a
/// department are both chosen. Education type has no effect on the
/// server (`Task` has no `education_type_id` column, same as the
/// original), so it only ever filters which stages the second dropdown
/// offers, purely client-side.
class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  int? _educationTypeId;
  int? _stageId;
  int? _departmentId;

  @override
  Widget build(BuildContext context) {
    final educationTypesAsync = ref.watch(taskEducationTypesProvider);
    final stagesAsync = ref.watch(taskStagesProvider);
    final departmentsAsync = ref.watch(taskDepartmentsProvider);

    final ready = _stageId != null && _departmentId != null;
    final tasksAsync =
        ready ? ref.watch(taskAdminListProvider((stageId: _stageId!, departmentId: _departmentId!))) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('المهام')),
      floatingActionButton: FloatingActionButton(
        // Carries the current filter over to the create form (see
        // TaskFormScreen's constructor) — null values when nothing's
        // filtered yet, in which case the form opens empty, same as before
        // this existed.
        onPressed: () => context.push(
          '/admin/tasks/new',
          extra: {'stageId': _stageId, 'educationTypeId': _educationTypeId},
        ),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const AcademicYearBanner(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                CascadingDropdown(
                  label: 'نوع الدراسة',
                  itemsAsync: educationTypesAsync,
                  value: _educationTypeId,
                  onChanged: (v) => setState(() {
                    _educationTypeId = v;
                    _stageId = null;
                    _departmentId = null;
                  }),
                ),
                const SizedBox(height: 8),
                // Keyed on the parent's value so the widget is fully
                // recreated (and its internal text resets) whenever the
                // education type changes — `DropdownMenu.initialSelection`
                // only applies on first build otherwise, same reasoning
                // as the day/service cascade in
                // `patient_registration_form_screen.dart`.
                CascadingDropdown(
                  key: ValueKey('stage-$_educationTypeId'),
                  label: 'المرحلة',
                  itemsAsync: stagesAsync.whenData(
                    (items) => _educationTypeId == null
                        ? items
                        : items.where((s) => s.educationTypeId == _educationTypeId).toList(),
                  ),
                  value: _stageId,
                  enabled: _educationTypeId != null,
                  onChanged: (v) => setState(() {
                    _stageId = v;
                    _departmentId = null;
                  }),
                ),
                const SizedBox(height: 8),
                CascadingDropdown(
                  key: ValueKey('department-$_stageId'),
                  label: 'القسم',
                  itemsAsync: departmentsAsync.whenData(
                    (items) => _stageId == null ? items : items.where((d) => d.stageId == _stageId).toList(),
                  ),
                  value: _departmentId,
                  enabled: _stageId != null,
                  onChanged: (v) => setState(() => _departmentId = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: !ready
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'اختر نوع الدراسة والمرحلة والقسم لعرض المهام.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : tasksAsync!.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, stackTrace) => Center(
                      child: Text(error is ApiException ? error.userMessage : 'تعذر التحميل.'),
                    ),
                    data: (page) {
                      if (page.items.isEmpty) {
                        return const Center(child: Text('لا توجد مهام مطابقة.'));
                      }
                      return RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(taskAdminListProvider((stageId: _stageId!, departmentId: _departmentId!))),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: page.items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) => _TaskTile(task: page.items[i]),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});
  final TaskAdmin task;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(task.title),
        subtitle: Text([
          if (task.departmentName != null) task.departmentName!,
          if (task.stageName != null) task.stageName!,
          if (task.caseSheetTypeNameAr != null) task.caseSheetTypeNameAr!,
        ].join(' · ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: task.isRequired
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                task.isRequired ? 'أساسية' : 'اختيارية',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: task.isRequired ? Theme.of(context).colorScheme.primary : null,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const Icon(Icons.chevron_left),
          ],
        ),
        onTap: () => context.push('/admin/tasks/${task.id}'),
      ),
    );
  }
}
