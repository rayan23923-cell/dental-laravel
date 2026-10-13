/// Mirrors `App\Http\Resources\TaskResource` — the Task *catalogue* entry
/// (a template a `TaskInstance` gets created from), distinct from
/// `TaskInstance`/`TaskSummary` (a specific doctor's assignment,
/// `features/task_instances/`).
class TaskAdmin {
  const TaskAdmin({
    required this.id,
    required this.title,
    required this.departmentId,
    required this.caseSheetTypeId,
    required this.stageId,
    required this.requiredCount,
    required this.notes,
    required this.grade,
    required this.departmentName,
    required this.caseSheetTypeNameAr,
    required this.stageName,
    required this.isRequired,
  });

  factory TaskAdmin.fromJson(Map<String, dynamic> json) => TaskAdmin(
        id: json['id'] as int,
        title: json['title'] as String? ?? '',
        departmentId: json['department_id'] as int?,
        caseSheetTypeId: json['case_sheet_type_id'] as int?,
        stageId: json['stage_id'] as int?,
        requiredCount: json['required_count'] as int?,
        notes: json['notes'] as String?,
        // Laravel's decimal cast serializes to a JSON *string* ("100.00"),
        // not a number — `as num?` threw here on any real graded task, the
        // same bug class as `Payment.fromJson` (Phase 5). Found live: this
        // screen had never actually been exercised against a task with a
        // non-null grade before the Phase 6 filters made that path reachable.
        grade: double.tryParse(json['grade']?.toString() ?? ''),
        departmentName: (json['department'] as Map<String, dynamic>?)?['name'] as String?,
        caseSheetTypeNameAr: (json['case_sheet_type'] as Map<String, dynamic>?)?['name_ar'] as String?,
        stageName: (json['stage'] as Map<String, dynamic>?)?['name'] as String?,
        // Defensive default matching the migration's own DB default, in
        // case an older cached response (from before this field existed)
        // is ever replayed.
        isRequired: json['is_required'] as bool? ?? true,
      );

  final int id;
  final String title;
  final int? departmentId;
  final int? caseSheetTypeId;
  final int? stageId;
  final int? requiredCount;
  final String? notes;
  final double? grade;
  final String? departmentName;
  final String? caseSheetTypeNameAr;
  final String? stageName;
  final bool isRequired;
}
