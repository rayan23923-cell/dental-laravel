import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/qr_dialog.dart';
import '../../case_sheet_forms/data/case_sheet_record_repository.dart';
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

  /// 'all' (the department view below), 'waiting' (start requests not yet
  /// approved) or 'notStarted' (tasks with slots still to start) —
  /// 2026-10-14, same as the web's "مهامي".
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
        final waiting = requests.where((r) => r.status != 'approved').toList();
        final pendingCount = requests.where((r) => r.status == 'pending').length;

        Widget pill(String key, String label, {int badge = 0}) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: ChoiceChip(
            label: Badge(isLabelVisible: badge > 0, label: Text('$badge'), offset: const Offset(14, -8), child: Text(label)),
            selected: _view == key,
            onSelected: (_) => setState(() => _view = key),
          ),
        );

        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  pill('all', t['taskRequests.allTasksTab']!),
                  pill('waiting', t['taskRequests.waitingTab']!, badge: pendingCount),
                  pill('notStarted', t['taskRequests.notStartedTab']!),
                ],
              ),
            ),
            if (_view == 'waiting')
              Expanded(child: _WaitingList(requests: waiting))
            else if (_view == 'notStarted')
              Expanded(
                child: _NotStartedList(departments: departments, requests: requests),
              )
            else ...[
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
          ],
        );
      },
    );
  }
}

class _DepartmentTaskList extends ConsumerWidget {
  const _DepartmentTaskList({required this.department});
  final MyTaskDepartment department;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = department.doctor.tasks;
    if (tasks.isEmpty) {
      final t = ref.watch(translationsProvider);
      return Center(child: Text(t['myTasks.noTasksInDept']!));
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
      children: [for (final entry in byTask.entries) _TaskGroupTile(slots: entry.value)],
    );
  }
}

class _TaskGroupTile extends ConsumerWidget {
  const _TaskGroupTile({required this.slots});
  final List<TaskSlotCard> slots;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = slots.first.taskTitle;
    final completed = slots.where((s) => s.status == 'completed').length;
    final required = slots.length;
    final t = ref.watch(translationsProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(title),
        subtitle: Text(trf(t['myTasks.completedOfRequired']!, {'completed': completed, 'required': required})),
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
          if (slot.instanceId == null) _RequestStartButton(taskId: slot.taskId, taskTitle: slot.taskTitle),
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
          else if (slot.instanceId != null)
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
          _openingCaseSheet
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
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

/// Tasks that still have slots to start, each with its request button.
class _NotStartedList extends ConsumerWidget {
  const _NotStartedList({required this.departments, required this.requests});
  final List<MyTaskDepartment> departments;
  final List<TaskStartRequest> requests;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final rows = <({String department, TaskSlotCard slot, int open})>[];
    for (final d in departments) {
      final byTask = <int, List<TaskSlotCard>>{};
      for (final card in d.doctor.tasks) {
        byTask.putIfAbsent(card.taskId, () => []).add(card);
      }
      for (final slots in byTask.values) {
        final open = slots.where((s) => s.instanceId == null).length;
        if (open > 0) rows.add((department: d.name, slot: slots.first, open: open));
      }
    }
    if (rows.isEmpty) {
      return Center(
        child: Text(t['taskRequests.noNotStarted']!, style: const TextStyle(color: Colors.grey)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final row in rows)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(row.slot.taskTitle),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.department),
                  _RequestStartButton(taskId: row.slot.taskId, taskTitle: row.slot.taskTitle),
                ],
              ),
            ),
          ),
      ],
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
