/// A doctor's request to start a task (2026-10-14) — see the web's
/// `App\Models\TaskStartRequest::toView()`.
class TaskStartRequest {
  const TaskStartRequest({
    required this.id,
    required this.status,
    required this.formType,
    required this.notes,
    required this.photoUrl,
    required this.caseSheetResource,
    required this.caseSheetRecordId,
    required this.createdAt,
    required this.reviewedAt,
    required this.reviewNote,
    required this.reviewer,
    required this.doctorName,
    required this.doctorStage,
    required this.doctorPhotoUrl,
    required this.taskId,
    required this.taskTitle,
    required this.department,
  });

  factory TaskStartRequest.fromJson(Map<String, dynamic> json) {
    final doctor = json['doctor'] as Map<String, dynamic>? ?? const {};
    final task = json['task'] as Map<String, dynamic>? ?? const {};
    final sheet = json['case_sheet'] as Map<String, dynamic>?;
    return TaskStartRequest(
      id: json['id'] as int,
      status: json['status'] as String? ?? 'pending',
      formType: json['form_type'] as String? ?? 'electronic',
      notes: json['notes'] as String?,
      photoUrl: json['photo_url'] as String?,
      caseSheetResource: sheet?['resource'] as String?,
      caseSheetRecordId: sheet?['record_id'] as int?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      reviewedAt: DateTime.tryParse(json['reviewed_at'] as String? ?? ''),
      reviewNote: json['review_note'] as String?,
      reviewer: json['reviewer'] as String?,
      doctorName: doctor['name'] as String? ?? '',
      doctorStage: doctor['stage'] as String?,
      doctorPhotoUrl: doctor['photo_url'] as String?,
      taskId: task['id'] as int? ?? 0,
      taskTitle: task['title'] as String? ?? '',
      department: task['department'] as String?,
    );
  }

  final int id;
  final String status; // pending | approved | rejected
  final String formType; // electronic | paper
  final String? notes;
  final String? photoUrl;
  final String? caseSheetResource;
  final int? caseSheetRecordId;
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final String? reviewer;
  final String doctorName;
  final String? doctorStage;
  final String? doctorPhotoUrl;
  final int taskId;
  final String taskTitle;
  final String? department;

  bool get isPaper => formType == 'paper';
}

/// The staff list: waiting, started and turned down.
class TaskStartRequestBoard {
  const TaskStartRequestBoard({required this.pending, required this.approved, required this.rejected});

  factory TaskStartRequestBoard.fromJson(Map<String, dynamic> json) {
    List<TaskStartRequest> list(String key) =>
        ((json[key] as List<dynamic>?) ?? const []).map((e) => TaskStartRequest.fromJson(e as Map<String, dynamic>)).toList();
    return TaskStartRequestBoard(pending: list('pending'), approved: list('approved'), rejected: list('rejected'));
  }

  final List<TaskStartRequest> pending;
  final List<TaskStartRequest> approved;
  final List<TaskStartRequest> rejected;
}
