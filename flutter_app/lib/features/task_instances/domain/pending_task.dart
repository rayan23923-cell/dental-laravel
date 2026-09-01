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
    // `Task.grade` is cast `decimal:2` server-side, which Laravel
    // serializes as a JSON *string* (e.g. `"100.00"`), not a number — the
    // same recurring bug already fixed for `TaskInstance.grade` (see that
    // file's own doc comment, also `TaskAdmin.grade` and `Payment.amount`)
    // — a plain `as num?` throws on any real graded task instead of
    // parsing it. Reproduced live: a task with a real grade (matching
    // what the user's own screenshot showed, "الدرجة: 100.00") crashed
    // this screen with the generic error message, while every task this
    // screen's own earlier testing used happened to have `grade: null`,
    // so this never surfaced then.
    grade: double.tryParse(json['grade']?.toString() ?? ''),
  );

  final int id;
  final String title;
  final String? department;
  final int requiredCount;
  final String? notes;
  final double? grade;
}
