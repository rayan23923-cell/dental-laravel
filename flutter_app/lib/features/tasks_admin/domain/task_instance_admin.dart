import '../../task_instances/domain/task_instance_status.dart';

/// One doctor's assignment of a task, as the task detail screen lists it
/// (`GET /tasks/{id}`'s `instances`, each a `TaskInstanceResource` with its
/// `doctor`) — the web `Tasks/Show.vue` table's row.
class TaskInstanceAdmin {
  const TaskInstanceAdmin({
    required this.id,
    required this.doctorId,
    required this.doctorName,
    required this.status,
    required this.assignedDate,
    required this.completionDate,
    required this.grade,
    required this.notes,
  });

  factory TaskInstanceAdmin.fromJson(Map<String, dynamic> json) => TaskInstanceAdmin(
        id: json['id'] as int,
        doctorId: json['doctor_id'] as int?,
        doctorName: (json['doctor'] as Map<String, dynamic>?)?['name'] as String?,
        status: TaskInstanceStatus.fromJson(json['status'] as String? ?? 'pending'),
        assignedDate: DateTime.tryParse(json['assigned_date']?.toString() ?? '')?.toLocal(),
        completionDate: DateTime.tryParse(json['completion_date']?.toString() ?? '')?.toLocal(),
        // A decimal cast arrives as a string ("9.00"), see TaskAdmin.grade.
        grade: double.tryParse(json['grade']?.toString() ?? ''),
        notes: json['notes'] as String?,
      );

  final int id;
  final int? doctorId;
  final String? doctorName;
  final TaskInstanceStatus status;
  final DateTime? assignedDate;
  final DateTime? completionDate;
  final double? grade;
  final String? notes;
}
