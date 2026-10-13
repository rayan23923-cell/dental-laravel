import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/academic_year_banner.dart';
import '../../../core/widgets/cascading_dropdown.dart';
import '../../../core/widgets/chat_list_tile.dart';
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
    final t = ref.watch(translationsProvider);

    final ready = _stageId != null && _departmentId != null;
    final tasksAsync =
        ready ? ref.watch(taskAdminListProvider((stageId: _stageId!, departmentId: _departmentId!))) : null;

    return Scaffold(
      appBar: AppBar(title: Text(t['tasksAdmin.title']!)),
      floatingActionButton: FloatingActionButton(
        // Carries the current filter over to the create form (see
        // TaskFormScreen's constructor) — null values when nothing's
        // filtered yet, in which case the form opens empty, same as before
        // this existed.
        onPressed: () => context.push(
          '/admin/tasks/new',
          extra: {'stageId': _stageId, 'educationTypeId': _educationTypeId},
        ),
        tooltip: t['tasksAdmin.newTitle'],
        child: const Icon(Icons.add_task),
      ),
      body: Column(
        children: [
          const AcademicYearBanner(),
          // Chat-list style (2026-10-13, by request): compact rounded
          // filter pills instead of three stacked outlined fields.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Theme(
              data: _pillFilterTheme(context),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: CascadingDropdown(
                          label: t['tasksAdmin.educationTypeLabel']!,
                          itemsAsync: educationTypesAsync,
                          value: _educationTypeId,
                          onChanged: (v) => setState(() {
                            _educationTypeId = v;
                            _stageId = null;
                            _departmentId = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Keyed on the parent's value so the widget is fully
                      // recreated (and its internal text resets) whenever the
                      // education type changes — `DropdownMenu.initialSelection`
                      // only applies on first build otherwise, same reasoning
                      // as the day/service cascade in
                      // `patient_registration_form_screen.dart`.
                      Expanded(
                        child: CascadingDropdown(
                          key: ValueKey('stage-$_educationTypeId'),
                          label: t['tasksAdmin.stageLabel']!,
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CascadingDropdown(
                    key: ValueKey('department-$_stageId'),
                    label: t['tasksAdmin.departmentLabel']!,
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
          ),
          Expanded(
            child: !ready
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.filter_alt_outlined, size: 48, color: Colors.black26),
                          const SizedBox(height: 8),
                          Text(
                            t['tasksAdmin.emptyPrompt']!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )
                : tasksAsync!.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, stackTrace) => Center(
                      child: Text(error is ApiException ? error.userMessage : t['tasksAdmin.loadFailed']!),
                    ),
                    data: (page) {
                      if (page.items.isEmpty) {
                        return Center(child: Text(t['tasksAdmin.emptyList']!));
                      }
                      return RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(taskAdminListProvider((stageId: _stageId!, departmentId: _departmentId!))),
                        child: ListView.separated(
                          padding: const EdgeInsets.only(top: 4, bottom: 88),
                          itemCount: page.items.length,
                          separatorBuilder: (_, __) => chatDivider,
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

/// Chat-list row (2026-10-13, by request): task icon, title, a
/// required/optional chip and the case-sheet type. Stage and department are
/// left out — the list only shows once both are picked in the filters above.
class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});
  final TaskAdmin task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final color = chatToneFor(task.id);
    return ChatListTile(
      title: task.title,
      color: color,
      icon: Icons.assignment_outlined,
      chips: [
        task.isRequired
            ? ChatChip(label: t['tasksAdmin.required']!, icon: Icons.star_rounded, color: Colors.indigo)
            : ChatChip(label: t['tasksAdmin.optional']!, icon: Icons.star_border_rounded, color: Colors.blueGrey),
        if (task.caseSheetTypeNameAr != null)
          ChatChip(label: task.caseSheetTypeNameAr!, icon: Icons.description_outlined, color: Colors.teal),
      ],
      onTap: () => context.push('/admin/tasks/${task.id}'),
    );
  }
}

/// Rounded, dense "pill" look for the filter dropdowns above a chat list.
ThemeData _pillFilterTheme(BuildContext context) {
  final theme = Theme.of(context);
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(30),
    borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
  );
  return theme.copyWith(
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: theme.colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        border: border,
        enabledBorder: border,
        constraints: const BoxConstraints(maxHeight: 44),
        labelStyle: const TextStyle(fontSize: 13),
      ),
      textStyle: const TextStyle(fontSize: 13),
    ),
  );
}
