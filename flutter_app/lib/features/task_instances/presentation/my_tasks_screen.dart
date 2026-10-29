import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/qr_dialog.dart';
import '../../case_sheet_forms/data/case_sheet_record_repository.dart';
import '../../form_settings/data/form_settings_repository.dart';
import '../../form_settings/presentation/supervisor_code_sheet.dart';
import '../../paper_photos/presentation/paper_photos_sheet.dart';
import '../../task_progress_admin/domain/task_progress_group.dart';
import '../../task_start_requests/data/task_start_request_repository.dart';
import '../../task_start_requests/domain/task_start_request.dart';
import '../../task_start_requests/presentation/request_start_sheet.dart';
import '../../task_start_requests/presentation/task_start_request_providers.dart';
import '../data/task_instance_repository.dart';
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
/// at all. A filter row on top (2026-10-29) narrows the slots by status.
class MyTasksScreen extends ConsumerStatefulWidget {
  const MyTasksScreen({super.key});

  @override
  ConsumerState<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends ConsumerState<MyTasksScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  int _departmentCount = -1;

  /// The filter row at the top (2026-10-29, by request): 'all',
  /// 'inProgress', 'completed', 'notStarted' filter the department view's
  /// slots by status; 'waiting' shows start requests not yet approved.
  String _view = 'all';

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
    final t = ref.watch(translationsProvider);

    return departmentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _ErrorView(error: error, onRetry: () => ref.invalidate(myTaskProgressProvider)),
      data: (departments) {
        _ensureTabController(departments.length);

        if (departments.isEmpty) {
          return Center(child: Text(t['myTasks.noDepartments']!));
        }

        final requests = ref.watch(myTaskStartRequestsProvider).valueOrNull ?? const <TaskStartRequest>[];
        // The pending lists switched off for the whole system (2026-10-22).
        final listsOn = (ref.watch(myFormSettingsProvider).valueOrNull ?? const DoctorFormSettings()).on('task_lists_enabled');
        if (!listsOn && _view != 'all') _view = 'all';
        final waiting = requests.where((r) => r.status != 'approved').toList();
        final pendingCount = requests.where((r) => r.status == 'pending').length;

        final slots = [for (final d in departments) ...d.doctor.tasks];
        int count(String filter) => slots.where((s) => _slotMatches(s, filter)).length;
        final completed = count('completed');
        final colors = Theme.of(context).colorScheme;

        final filters = <({String key, String label, IconData icon, Color color, int count})>[
          (key: 'all', label: t['myTasks.filterAll']!, icon: Icons.apps_rounded, color: colors.primary, count: slots.length),
          if (listsOn) ...[
            (key: 'inProgress', label: t['myTasks.filterInProgress']!, icon: Icons.timelapse_rounded, color: Colors.blue.shade700, count: count('inProgress')),
            (key: 'completed', label: t['myTasks.filterCompleted']!, icon: Icons.task_alt_rounded, color: Colors.green.shade700, count: completed),
            (key: 'notStarted', label: t['myTasks.filterNotStarted']!, icon: Icons.radio_button_unchecked_rounded, color: Colors.blueGrey.shade600, count: count('notStarted')),
            (key: 'waiting', label: t['taskRequests.waitingTab']!, icon: Icons.hourglass_top_rounded, color: Colors.orange.shade800, count: pendingCount),
          ],
        ];

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  for (final f in filters)
                    Expanded(
                      child: _StatusFilterTile(
                        label: f.label,
                        icon: f.icon,
                        color: f.color,
                        count: f.count,
                        selected: _view == f.key,
                        onTap: () => setState(() => _view = f.key),
                      ),
                    ),
                ],
              ),
            ),
            // Overall progress (with the completed counts' switch).
            if (listsOn && slots.isNotEmpty && _view != 'waiting') _ProgressSummary(completed: completed, required: slots.length),
            if (_view == 'waiting')
              Expanded(child: _WaitingList(requests: waiting))
            else ...[
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: [
                  for (final d in departments)
                    Tab(
                      text: _view == 'all' ? d.name : '${d.name} (${d.doctor.tasks.where((s) => _slotMatches(s, _view)).length})',
                    ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [for (final d in departments) _DepartmentTaskList(department: d, filter: _view)],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Whether [slot] belongs under the top filter [filter]. A 'pending'
/// instance has no doctor yet, so for the doctor it counts as not started.
bool _slotMatches(TaskSlotCard slot, String filter) => switch (filter) {
  'inProgress' => slot.status == 'assigned',
  'completed' => slot.status == 'completed',
  'notStarted' => slot.status == 'unassigned' || slot.status == 'pending',
  _ => true,
};

/// One tile of the filter row: the count on top, icon and label under it,
/// filled with its own color when selected. Tiles share the width so the
/// whole row fits a phone screen.
class _StatusFilterTile extends StatelessWidget {
  const _StatusFilterTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 78,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? color : color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? color : color.withValues(alpha: 0.22)),
              boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))] : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 15, color: foreground),
                    const SizedBox(width: 4),
                    Text('$count', style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 18, height: 1.1)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: foreground, fontWeight: FontWeight.w600, fontSize: 11, height: 1.15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "أنجزت X من Y حالة" with a progress bar, under the filter row.
class _ProgressSummary extends ConsumerWidget {
  const _ProgressSummary({required this.completed, required this.required});
  final int completed;
  final int required;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final ratio = required == 0 ? 0.0 : completed / required;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        children: [
          Text(
            trf(t['myTasks.progressSummary']!, {'completed': completed, 'required': required}),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: ratio, minHeight: 6, color: Colors.green.shade600, backgroundColor: Colors.green.withValues(alpha: 0.15)),
            ),
          ),
          const SizedBox(width: 8),
          Text('${(ratio * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class _DepartmentTaskList extends ConsumerWidget {
  const _DepartmentTaskList({required this.department, required this.filter});
  final MyTaskDepartment department;
  final String filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = department.doctor.tasks.where((s) => _slotMatches(s, filter)).toList();
    if (tasks.isEmpty) {
      final t = ref.watch(translationsProvider);
      final filtered = filter != 'all' && department.doctor.tasks.isNotEmpty;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (filtered) Icon(Icons.filter_alt_off_outlined, size: 40, color: Theme.of(context).colorScheme.outline),
            if (filtered) const SizedBox(height: 8),
            Text(filtered ? t['myTasks.noTasksForFilter']! : t['myTasks.noTasksInDept']!, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // Group this department's slot cards by task_id, preserving the
    // backend's own task ordering (grouped by title) — a `Map` insertion
    // order is stable in Dart, so no extra sort needed.
    final byTask = <int, List<TaskSlotCard>>{};
    for (final card in tasks) {
      byTask.putIfAbsent(card.taskId, () => []).add(card);
    }
    // The "X/N مكتملة" line counts every slot of the task, not just the filtered ones.
    final allSlots = <int, List<TaskSlotCard>>{};
    for (final card in department.doctor.tasks) {
      allSlots.putIfAbsent(card.taskId, () => []).add(card);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final entry in byTask.entries)
          _TaskGroupTile(
            // A new key per filter so a filtered list opens expanded.
            key: ValueKey('${entry.key}-$filter'),
            slots: entry.value,
            allSlots: allSlots[entry.key]!,
            expanded: filter != 'all',
          ),
      ],
    );
  }
}

class _TaskGroupTile extends ConsumerWidget {
  const _TaskGroupTile({super.key, required this.slots, required this.allSlots, this.expanded = false});
  final List<TaskSlotCard> slots;
  final List<TaskSlotCard> allSlots;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = slots.first.taskTitle;
    final completed = allSlots.where((s) => s.status == 'completed').length;
    final required = allSlots.length;
    final t = ref.watch(translationsProvider);
    final listsOn = (ref.watch(myFormSettingsProvider).valueOrNull ?? const DoctorFormSettings()).on('task_lists_enabled');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        title: Text(title),
        // The completed count goes with the pending lists' switch (2026-10-22).
        subtitle: listsOn ? Text(trf(t['myTasks.completedOfRequired']!, {'completed': completed, 'required': required})) : null,
        children: [for (final slot in slots) _SlotRow(slot: slot)],
      ),
    );
  }
}

class _SlotRow extends ConsumerStatefulWidget {
  const _SlotRow({required this.slot});
  final TaskSlotCard slot;

  @override
  ConsumerState<_SlotRow> createState() => _SlotRowState();
}

class _SlotRowState extends ConsumerState<_SlotRow> {
  TaskSlotCard get slot => widget.slot;
  bool _openingCaseSheet = false;

  /// Same resolve-or-create linkage as `TaskInstanceDetailScreen`'s
  /// `_openCaseSheet()` — duplicated rather than shared because that
  /// screen doesn't have a `TaskSlotCard` to build a `_SlotRow` from and
  /// the method itself is only a few lines; not worth a third file for.
  Future<void> _openCaseSheet() async {
    final instanceId = slot.instanceId;
    if (instanceId == null) return;

    setState(() => _openingCaseSheet = true);
    try {
      final result = await ref.read(caseSheetRecordRepositoryProvider).openFor(instanceId);
      if (!mounted) return;
      final query = '?task_instances_id=$instanceId';
      context.push(
        result.recordId != null ? '/case-sheets/${result.resource}/${result.recordId}$query' : '/case-sheets/${result.resource}/new$query',
      );
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

  /// The optional pre-instance draft (2026-08-28) — same idea as
  /// [_openCaseSheet], but for a slot that hasn't started yet: no real
  /// `TaskInstance` exists, so this resolves/creates a standalone draft
  /// keyed by (doctor, task) instead — see `Api\CaseSheetController::openForTask()`'s
  /// doc comment for why this deliberately never starts the task itself
  /// (that still requires the normal QR-scan/screening-gated flow).
  Future<void> _openCaseSheetForTask() async {
    setState(() => _openingCaseSheet = true);
    try {
      final result = await ref.read(caseSheetRecordRepositoryProvider).openForTask(slot.taskId);
      if (!mounted) return;
      final query = '?task_id=${slot.taskId}';
      context.push(
        result.recordId != null ? '/case-sheets/${result.resource}/${result.recordId}$query' : '/case-sheets/${result.resource}/new$query',
      );
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

  /// "تأكيد أنه ورقي" (2026-08-28) — non-exclusive, never hides or
  /// disables the electronic "نموذج سريري" button next to it; see
  /// `Api\TaskInstanceController::confirmPaper()`'s doc comment.
  Future<void> _confirmPaper() async {
    final instanceId = slot.instanceId;
    if (instanceId == null) return;
    final t = ref.read(translationsProvider);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t['myTasks.confirmPaperMsg']!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t['nav.cancel']!)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t['myTasks.confirm']!)),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(taskInstanceRepositoryProvider).confirmPaper(instanceId);
      invalidateTaskInstance(ref, instanceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['myTasks.paperConfirmedSuccess']!)));
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['profile.saveFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  /// The supervisor's code on this account (2026-10-22, by request).
  Future<void> _supervisorCode(DoctorFormSettings settings) async {
    final name = await showSupervisorCodeSheet(
      context,
      settings: settings,
      taskId: slot.taskId,
      taskTitle: slot.taskTitle,
      slot: slot.slot,
      instanceId: slot.instanceId,
      taskGrade: slot.taskGrade,
    );
    if (name == null || !mounted) return;
    final t = ref.read(translationsProvider);
    ref.invalidate(myTaskProgressProvider);
    ref.invalidate(myTaskStartRequestsProvider);
    if (slot.instanceId != null) invalidateTaskInstance(ref, slot.instanceId!);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Colors.green.shade700, content: Text(t['supervisorCode.done']!.replaceAll('{name}', name))),
    );
  }

  Color _statusColor(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return switch (slot.status) {
      'completed' => Colors.green,
      'assigned' => colors.primary,
      'pending' => Colors.orange,
      _ => colors.outline,
    };
  }

  String _statusLabel(Map<String, String> t) => switch (slot.status) {
    'completed' => t['slotStatus.completed']!,
    'assigned' => t['slotStatus.inProgress']!,
    'pending' => t['slotStatus.pending']!,
    _ => t['slotStatus.notStarted']!,
  };

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final date = slot.completionDate ?? slot.assignedDate;
    final parsedDate = date != null ? DateTime.tryParse(date) : null;
    final t = ref.watch(translationsProvider);
    // Forms on offer and the supervisor code (2026-10-22).
    final settings = ref.watch(myFormSettingsProvider).valueOrNull ?? const DoctorFormSettings();
    final showCode = (slot.status == 'unassigned' && settings.codeCanStart) || (slot.status == 'assigned' && settings.codeCanProgress);

    return ListTile(
      title: Text(trf(t['myTasks.slotTitle']!, {'slot': slot.slot})),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: _statusColor(context).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                child: Text(
                  _statusLabel(t),
                  style: TextStyle(color: _statusColor(context), fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
              if (slot.grade != null) ...[
                const SizedBox(width: 8),
                Text(trf(t['myTasks.gradeLine']!, {'grade': slot.grade!})),
              ],
            ],
          ),
          if (parsedDate != null) Text(dateFormat.format(parsedDate)),
          if (slot.notes != null && slot.notes!.isNotEmpty) Text(slot.notes!),
          // Ask staff to start it (2026-10-14) — or show it's waiting.
          if (slot.instanceId == null && settings.on('task_start_enabled')) _RequestStartButton(taskId: slot.taskId, taskTitle: slot.taskTitle),
          if (showCode)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.deepPurple.shade50,
                  foregroundColor: Colors.deepPurple.shade700,
                ),
                onPressed: () => _supervisorCode(settings),
                icon: const Icon(Icons.pin_outlined, size: 18),
                label: Text(
                  slot.status == 'assigned' && slot.stepsCount > 0
                      ? '${t['supervisorCode.button']!} (${slot.stepsSigned}/${slot.stepsCount})'
                      : t['supervisorCode.button']!,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          // "تأكيد أنه ورقي" — only meaningful once the case has a real
          // instance (an unstarted slot's optional draft isn't a
          // documented case yet).
          if (slot.instanceId != null && slot.paperCaseSheetConfirmedAt != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, size: 14, color: Colors.amber),
                const SizedBox(width: 4),
                Text(t['myTasks.confirmedOnPaper']!, style: const TextStyle(fontSize: 12)),
              ],
            )
          else if (slot.instanceId != null && settings.paper)
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), visualDensity: VisualDensity.compact),
              onPressed: _confirmPaper,
              child: Text(t['myTasks.confirmPaperButton']!, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
      // QR always shown — even an unstarted slot has one, since scanning
      // it is how an admin/senior *starts* it (the task+doctor
      // "pending_task" QR, same one already used on the web's "رموز
      // المهام المعلقة" page). Every remaining unstarted slot of the same
      // task shows the identical code — there's no finer-grained identity
      // until one is actually claimed (see `TaskStarter`'s pending-slot
      // pooling). "نموذج سريري" is now shown on unstarted slots too
      // (2026-08-28) — optional prep notes via [_openCaseSheetForTask],
      // deliberately not linked to a real instance yet.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: t['labels.qrCode']!,
            onPressed: () => showQrDialog(
              context,
              imagePath: slot.instanceId != null ? '/task-instances/${slot.instanceId}/qr' : '/pending-tasks/${slot.taskId}/qr',
              title: slot.instanceId != null ? t['myTasks.qrCaseTitle']! : t['myTasks.qrStartTitle']!,
              caption: slot.instanceId != null ? t['myTasks.qrCaseCaption']! : t['myTasks.qrStartCaption']!,
            ),
          ),
          // Photos next to the form (2026-10-15, as on the web): the doctor
          // uploads, the supervisor previews them and writes notes.
          if (settings.paper)
          IconButton(
            tooltip: slot.instanceId != null ? t['paperPhotos.uploadShort']! : t['paperPhotos.needsStart']!,
            onPressed: slot.instanceId == null
                ? null
                : () async {
                    await showPaperPhotosSheet(context, instanceId: slot.instanceId!, title: slot.taskTitle, doctor: true);
                    ref.invalidate(myTaskProgressProvider);
                  },
            icon: Badge(
              isLabelVisible: slot.attachmentsCount > 0 || slot.notedAttachmentsCount > 0,
              backgroundColor: slot.notedAttachmentsCount > 0 ? Colors.amber.shade700 : Colors.green,
              label: Text('${slot.notedAttachmentsCount > 0 ? slot.notedAttachmentsCount : slot.attachmentsCount}'),
              child: const Icon(Icons.add_a_photo_outlined),
            ),
          ),
          if (!settings.electronic)
            const SizedBox.shrink()
          else if (_openingCaseSheet)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.description_outlined),
              tooltip: t['labels.caseSheetForm']!,
              onPressed: slot.instanceId != null ? _openCaseSheet : _openCaseSheetForTask,
            ),
          if (slot.instanceId != null) const Icon(Icons.chevron_left),
        ],
      ),
      onTap: slot.instanceId != null ? () => context.push('/tasks/${slot.instanceId}') : null,
    );
  }
}

/// Opens the doctor's pre-instance draft of [taskId]'s case sheet — the
/// "electronic form" a start request points staff at.
Future<void> _openTaskDraft(BuildContext context, WidgetRef ref, int taskId) async {
  try {
    final result = await ref.read(caseSheetRecordRepositoryProvider).openForTask(taskId);
    if (!context.mounted) return;
    final query = '?task_id=$taskId';
    context.push(
      result.recordId != null ? '/case-sheets/${result.resource}/${result.recordId}$query' : '/case-sheets/${result.resource}/new$query',
    );
  } catch (e) {
    if (context.mounted) {
      final t = ref.read(translationsProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.userMessage : t['myTasks.openFormFailed']!)));
    }
  }
}

/// "طلب بدء" for a task with slots still to start, or a "بانتظار الموافقة"
/// chip once a request is waiting.
class _RequestStartButton extends ConsumerWidget {
  const _RequestStartButton({required this.taskId, required this.taskTitle});
  final int taskId;
  final String taskTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final requests = ref.watch(myTaskStartRequestsProvider).valueOrNull ?? const <TaskStartRequest>[];
    if (requests.any((r) => r.taskId == taskId && r.status == 'pending')) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top, size: 14, color: Colors.orange.shade700),
            const SizedBox(width: 4),
            Text(t['taskRequests.waitingApproval']!, style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
          ],
        ),
      );
    }
    return TextButton.icon(
      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), visualDensity: VisualDensity.compact),
      icon: const Icon(Icons.send_outlined, size: 16),
      label: Text(t['taskRequests.requestStart']!, style: const TextStyle(fontSize: 12)),
      onPressed: () async {
        final sent = await showRequestStartSheet(
          context,
          taskId: taskId,
          taskTitle: taskTitle,
          onOpenForm: () => _openTaskDraft(context, ref, taskId),
        );
        if (sent) {
          ref.invalidate(myTaskStartRequestsProvider);
          ref.invalidate(myTaskProgressProvider);
        }
      },
    );
  }
}

/// Requests still waiting for staff, plus turned-down ones with the reason.
class _WaitingList extends ConsumerWidget {
  const _WaitingList({required this.requests});
  final List<TaskStartRequest> requests;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(myTaskStartRequestsProvider.future),
      child: requests.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 80),
                Text(
                  t['taskRequests.noWaiting']!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final r in requests)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        r.status == 'pending' ? Icons.hourglass_top : Icons.cancel_outlined,
                        color: r.status == 'pending' ? Colors.orange.shade700 : Colors.red.shade700,
                      ),
                      title: Text(r.taskTitle),
                      subtitle: Text(
                        [
                          if (r.department != null) r.department!,
                          r.isPaper ? t['taskRequests.paperForm']! : t['taskRequests.electronicForm']!,
                          r.status == 'pending' ? t['taskRequests.waitingApproval']! : t['taskRequests.rejectedShort']!,
                          if (r.status == 'rejected' && r.reviewNote != null && r.reviewNote!.isNotEmpty) r.reviewNote!,
                        ].join(' · '),
                      ),
                      trailing: r.status == 'pending'
                          ? IconButton(
                              icon: const Icon(Icons.undo),
                              tooltip: t['taskRequests.cancel'],
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    content: Text(t['taskRequests.cancelConfirm']!),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t['nav.cancel']!)),
                                      FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t['taskRequests.cancel']!)),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                try {
                                  await ref.read(taskStartRequestRepositoryProvider).cancel(r.id);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e is ApiException ? e.userMessage : t['taskRequests.actionFailed']!)),
                                    );
                                  }
                                }
                                ref.invalidate(myTaskStartRequestsProvider);
                              },
                            )
                          : null,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final message = error is ApiException ? (error as ApiException).userMessage : t['common.unexpectedError']!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(t['common.retry']!)),
        ],
      ),
    );
  }
}
