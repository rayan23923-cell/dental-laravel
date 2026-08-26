/// The nested `task` object `TaskInstanceResource` embeds — a partial view
/// of the full `Task` (id, title, department, case_sheet_type only; see
/// `App\Http\Resources\TaskInstanceResource` for exactly which fields).
class TaskSummary {
  const TaskSummary({
    required this.id,
    required this.title,
    required this.departmentName,
    required this.caseSheetTypeNameAr,
    required this.caseSheetTypeNameEn,
  });

  factory TaskSummary.fromJson(Map<String, dynamic> json) {
    final department = json['department'] as Map<String, dynamic>?;
    final caseSheetType = json['case_sheet_type'] as Map<String, dynamic>?;

    return TaskSummary(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      departmentName: department?['name'] as String?,
      caseSheetTypeNameAr: caseSheetType?['name_ar'] as String?,
      caseSheetTypeNameEn: caseSheetType?['name_en'] as String?,
    );
  }

  final int id;
  final String title;
  final String? departmentName;
  final String? caseSheetTypeNameAr;
  final String? caseSheetTypeNameEn;
}
