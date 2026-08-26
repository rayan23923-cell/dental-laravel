import 'task_instance_status.dart';
import 'task_summary.dart';

/// Mirrors `App\Http\Resources\TaskInstanceResource`.
class TaskInstance {
  const TaskInstance({
    required this.id,
    required this.taskId,
    required this.doctorId,
    required this.status,
    required this.assignedDate,
    required this.completionDate,
    required this.notes,
    required this.grade,
    required this.doctorName,
    required this.doctorUsername,
    required this.assignedByName,
    required this.task,
  });

  factory TaskInstance.fromJson(Map<String, dynamic> json) {
    final doctor = json['doctor'] as Map<String, dynamic>?;
    final task = json['task'] as Map<String, dynamic>?;

    return TaskInstance(
      id: json['id'] as int,
      taskId: json['task_id'] as int,
      doctorId: json['doctor_id'] as int,
      status: TaskInstanceStatus.fromJson(json['status'] as String),
      assignedDate: _parseDate(json['assigned_date']),
      completionDate: _parseDate(json['completion_date']),
      notes: json['notes'] as String?,
      // Same `decimal:2` cast / JSON-string bug as `TaskAdmin.grade`
      // (Phase 6) and `Payment.amount` (Phase 5) — `TaskInstance.grade`
      // is cast the same way in `App\Models\TaskInstance`, so `as num?`
      // would throw here too on any real graded instance.
      grade: double.tryParse(json['grade']?.toString() ?? ''),
      doctorName: doctor?['name'] as String?,
      doctorUsername: doctor?['username'] as String?,
      assignedByName: json['assigned_by_name'] as String?,
      task: task != null ? TaskSummary.fromJson(task) : null,
    );
  }

  static DateTime? _parseDate(dynamic value) => value == null ? null : DateTime.tryParse(value as String);

  final int id;
  final int taskId;
  final int doctorId;
  final TaskInstanceStatus status;
  final DateTime? assignedDate;
  final DateTime? completionDate;
  final String? notes;
  final double? grade;

  /// Student/staff identity fields — the server omits `doctor`/
  /// `assigned_by_name` entirely (rather than sending them and expecting
  /// the client to hide them) unless the viewer is the owning doctor
  /// themselves or a staff `User` who is admin or holds `task_progress,view`
  /// (see `App\Support\TaskInstanceVisibility`). Null here can mean either
  /// "not authorized to see it" or "genuinely unset" — this screen doesn't
  /// need to tell those apart, it just doesn't render the row either way.
  final String? doctorName;
  final String? doctorUsername;
  final String? assignedByName;

  final TaskSummary? task;
}
