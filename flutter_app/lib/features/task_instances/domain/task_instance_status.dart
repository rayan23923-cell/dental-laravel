/// Mirrors `task_instances.status` — the exact 3 values
/// `TaskInstanceController::update()` validates against
/// (`in:pending,assigned,completed`).
enum TaskInstanceStatus {
  pending,
  assigned,
  completed;

  static TaskInstanceStatus fromJson(String value) => TaskInstanceStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => TaskInstanceStatus.pending,
      );

  String toJson() => name;

  String label(Map<String, String> t) => switch (this) {
        TaskInstanceStatus.pending => t['taskStatus.pending']!,
        TaskInstanceStatus.assigned => t['taskStatus.assigned']!,
        TaskInstanceStatus.completed => t['taskStatus.completed']!,
      };
}
