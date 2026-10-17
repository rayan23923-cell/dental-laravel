/// Mirrors `Api\DoctorTaskProgressController::show()` — one doctor's tasks
/// with completed/required counts, the same page the web's task-progress
/// scanner opens for a doctor's ID card QR (`doctors.progress`).
class DoctorProgress {
  const DoctorProgress({
    required this.id,
    required this.name,
    required this.username,
    required this.stage,
    required this.educationType,
    required this.group,
    required this.total,
    required this.completed,
    required this.assigned,
    required this.pending,
    required this.tasks,
  });

  factory DoctorProgress.fromJson(Map<String, dynamic> json) {
    final doctor = json['doctor'] as Map<String, dynamic>;
    final stats = (json['stats'] as Map<String, dynamic>?) ?? const {};
    return DoctorProgress(
      id: doctor['id'] as int,
      name: doctor['name'] as String? ?? '',
      username: doctor['username'] as String? ?? '',
      stage: doctor['stage'] as String?,
      educationType: doctor['education_type'] as String?,
      group: doctor['group'] as String?,
      total: stats['total'] as int? ?? 0,
      completed: stats['completed'] as int? ?? 0,
      assigned: stats['assigned'] as int? ?? 0,
      pending: stats['pending'] as int? ?? 0,
      tasks: [
        for (final t in (json['tasks'] as List? ?? const []))
          DoctorProgressTask.fromJson(t as Map<String, dynamic>),
      ],
    );
  }

  final int id;
  final String name;
  final String username;
  final String? stage;
  final String? educationType;
  final String? group;
  final int total;
  final int completed;
  final int assigned;
  final int pending;
  final List<DoctorProgressTask> tasks;
}

class DoctorProgressTask {
  const DoctorProgressTask({
    required this.taskId,
    required this.title,
    required this.department,
    required this.requiredCount,
    required this.completed,
    required this.remaining,
  });

  factory DoctorProgressTask.fromJson(Map<String, dynamic> json) => DoctorProgressTask(
        taskId: json['task_id'] as int,
        title: json['title'] as String? ?? '',
        department: json['department'] as String?,
        requiredCount: json['required_count'] as int? ?? 0,
        completed: json['completed'] as int? ?? 0,
        remaining: json['remaining'] as int? ?? 0,
      );

  final int taskId;
  final String title;
  final String? department;
  final int requiredCount;
  final int completed;
  final int remaining;
}
