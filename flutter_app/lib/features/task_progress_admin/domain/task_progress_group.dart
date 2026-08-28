/// Mirrors `App\Services\TaskProgressFilters::build()`'s and
/// `TaskProgressGroupSummary::build()`'s return shapes — the same day ->
/// education type/stage -> group -> department -> doctor matrix the web's
/// `TaskProgress/Index.vue` renders, fetched via `Api\TaskProgressController`'s
/// `filters()`/`group()` endpoints that delegate to those same services.
library;

import '../../../core/data/lookup_repository.dart';

class TaskProgressGroupOption {
  const TaskProgressGroupOption({required this.id, required this.name, this.stageName, this.educationTypeName});

  factory TaskProgressGroupOption.fromJson(Map<String, dynamic> json) => TaskProgressGroupOption(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        stageName: json['stage_name'] as String?,
        educationTypeName: json['education_type_name'] as String?,
      );

  final int id;
  final String name;
  final String? stageName;
  final String? educationTypeName;
}

class TaskProgressFilters {
  const TaskProgressFilters({required this.days, required this.educationTypes, required this.stages, required this.groups});

  factory TaskProgressFilters.fromJson(Map<String, dynamic> json) => TaskProgressFilters(
        days: (json['days'] as List<dynamic>).map((d) => d as String).toList(),
        educationTypes:
            (json['education_types'] as List<dynamic>).map((e) => LookupItem.fromJson(e as Map<String, dynamic>)).toList(),
        stages: (json['stages'] as List<dynamic>).map((e) => LookupItem.fromJson(e as Map<String, dynamic>)).toList(),
        groups: (json['groups'] as List<dynamic>)
            .map((e) => TaskProgressGroupOption.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final List<String> days;
  final List<LookupItem> educationTypes;
  final List<LookupItem> stages;
  final List<TaskProgressGroupOption> groups;
}

class TaskProgressCaseSheet {
  const TaskProgressCaseSheet({required this.name, this.color});

  factory TaskProgressCaseSheet.fromJson(Map<String, dynamic> json) => TaskProgressCaseSheet(
        name: json['name'] as String? ?? '',
        color: json['color'] as String?,
      );

  final String name;
  final String? color;
}

/// One positional task "slot" for a doctor — the original has no per-slot
/// foreign key, slots are matched to instances by index (see
/// `TaskProgressGroupSummary`'s docblock).
class TaskSlotCard {
  const TaskSlotCard({
    required this.slot,
    required this.taskId,
    required this.taskTitle,
    this.taskNotes,
    this.taskGrade,
    this.caseSheet,
    this.instanceId,
    required this.status,
    this.assignedDate,
    this.completionDate,
    this.notes,
    this.grade,
    this.startedByName,
    this.paperCaseSheetConfirmedAt,
  });

  factory TaskSlotCard.fromJson(Map<String, dynamic> json) => TaskSlotCard(
        slot: json['slot'] as int,
        taskId: json['task_id'] as int,
        taskTitle: json['task_title'] as String? ?? '',
        taskNotes: json['task_notes'] as String?,
        // Laravel's decimal cast serializes to a JSON *string* — the same
        // bug class `TaskAdmin.grade` already had (see task_admin.dart).
        taskGrade: double.tryParse(json['task_grade']?.toString() ?? ''),
        caseSheet: json['case_sheet'] != null ? TaskProgressCaseSheet.fromJson(json['case_sheet'] as Map<String, dynamic>) : null,
        instanceId: json['instance_id'] as int?,
        status: json['status'] as String? ?? 'unassigned',
        assignedDate: json['assigned_date'] as String?,
        completionDate: json['completion_date'] as String?,
        notes: json['notes'] as String?,
        grade: double.tryParse(json['grade']?.toString() ?? ''),
        startedByName: json['started_by'] as String?,
        paperCaseSheetConfirmedAt: json['paper_case_sheet_confirmed_at'] as String?,
      );

  final int slot;
  final int taskId;
  final String taskTitle;
  final String? taskNotes;
  final double? taskGrade;
  final TaskProgressCaseSheet? caseSheet;
  final int? instanceId;
  final String status; // pending | assigned | completed | unassigned
  final String? assignedDate;
  final String? completionDate;
  final String? notes;
  final double? grade;

  /// The staff member who started this task — null if never started
  /// (`status == 'unassigned'`) or that user has since been deleted.
  final String? startedByName;

  /// "شكرا، تم توثيقه ورقياً" (2026-08-28) — set once a doctor confirms
  /// this case is documented on paper; purely informational, never gates
  /// the electronic case-sheet flow. Null means "not confirmed."
  final String? paperCaseSheetConfirmedAt;
}

class TaskProgressDoctorRow {
  const TaskProgressDoctorRow({
    required this.id,
    required this.name,
    required this.username,
    required this.required,
    required this.completed,
    required this.assigned,
    required this.pending,
    required this.unassigned,
    required this.tasks,
  });

  factory TaskProgressDoctorRow.fromJson(Map<String, dynamic> json) => TaskProgressDoctorRow(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        username: json['username'] as String? ?? '',
        required: json['required'] as int? ?? 0,
        completed: json['completed'] as int? ?? 0,
        assigned: json['assigned'] as int? ?? 0,
        pending: json['pending'] as int? ?? 0,
        unassigned: json['unassigned'] as int? ?? 0,
        tasks: (json['tasks'] as List<dynamic>).map((e) => TaskSlotCard.fromJson(e as Map<String, dynamic>)).toList(),
      );

  final int id;
  final String name;
  final String username;
  final int required;
  final int completed;
  final int assigned;
  final int pending;
  final int unassigned;
  final List<TaskSlotCard> tasks;
}

class TaskProgressDepartment {
  const TaskProgressDepartment({
    required this.id,
    required this.name,
    required this.taskCount,
    required this.totalRequired,
    required this.doctors,
  });

  factory TaskProgressDepartment.fromJson(Map<String, dynamic> json) => TaskProgressDepartment(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        taskCount: json['task_count'] as int? ?? 0,
        totalRequired: json['total_required'] as int? ?? 0,
        doctors: (json['doctors'] as List<dynamic>).map((e) => TaskProgressDoctorRow.fromJson(e as Map<String, dynamic>)).toList(),
      );

  final int id;
  final String name;
  final int taskCount;
  final int totalRequired;
  final List<TaskProgressDoctorRow> doctors;
}

class TaskProgressGroupDetail {
  const TaskProgressGroupDetail({required this.groupOption, required this.departments});

  factory TaskProgressGroupDetail.fromJson(Map<String, dynamic> json) => TaskProgressGroupDetail(
        groupOption: TaskProgressGroupOption.fromJson(json['group'] as Map<String, dynamic>),
        departments:
            (json['departments'] as List<dynamic>).map((e) => TaskProgressDepartment.fromJson(e as Map<String, dynamic>)).toList(),
      );

  final TaskProgressGroupOption groupOption;
  final List<TaskProgressDepartment> departments;
}

/// `POST /task-progress/start`'s response — carries everything the
/// printed start-receipt needs (doctor name, task/department, notes,
/// start time) so the caller doesn't need a second round-trip just to
/// build the ticket.
class TaskStartResult {
  const TaskStartResult({
    required this.instanceId,
    required this.status,
    this.notes,
    this.assignedDate,
    required this.doctorName,
    required this.taskTitle,
    this.departmentName,
    this.startedByName,
  });

  factory TaskStartResult.fromJson(Map<String, dynamic> json) {
    final doctor = json['doctor'] as Map<String, dynamic>? ?? const {};
    final task = json['task'] as Map<String, dynamic>? ?? const {};
    return TaskStartResult(
      instanceId: json['instance_id'] as int,
      status: json['status'] as String? ?? '',
      notes: json['notes'] as String?,
      assignedDate: json['assigned_date'] as String?,
      doctorName: doctor['name'] as String? ?? '',
      taskTitle: task['title'] as String? ?? '',
      departmentName: task['department'] as String?,
      startedByName: json['started_by'] as String?,
    );
  }

  final int instanceId;
  final String status;
  final String? notes;
  final String? assignedDate;
  final String doctorName;
  final String taskTitle;
  final String? departmentName;

  /// The staff member who started this task (`TaskInstance::assigned_by`) —
  /// null if that user has since been deleted.
  final String? startedByName;
}
