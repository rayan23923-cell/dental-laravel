/// A task type in the doctor's own stage that they have **no** `TaskInstance`
/// of at all yet — see `App\Support\PendingTaskFinder`'s own docblock for
/// why that's a different sense of "pending" than `TaskInstanceStatus`.
/// Mirrors the web's `Doctor\PendingTasksQrController::index()` shape
/// exactly (`resources/js/Pages/Doctor/PendingTasksQr.vue`'s `tasks` prop).
class PendingTask {
  const PendingTask({
    required this.id,
    required this.title,
    required this.department,
    required this.requiredCount,
    required this.notes,
    required this.grade,
  });

  factory PendingTask.fromJson(Map<String, dynamic> json) => PendingTask(
    id: json['id'] as int,
    title: json['title'] as String? ?? '',
    department: json['department'] as String?,
    requiredCount: json['required_count'] as int? ?? 1,
    notes: json['notes'] as String?,
    grade: json['grade'] as num?,
  );

  final int id;
  final String title;
  final String? department;
  final int requiredCount;
  final String? notes;
  final num? grade;
}
