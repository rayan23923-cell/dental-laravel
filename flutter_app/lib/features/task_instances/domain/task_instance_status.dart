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

  String get arabicLabel => switch (this) {
        TaskInstanceStatus.pending => 'قيد الانتظار',
        TaskInstanceStatus.assigned => 'مسندة',
        TaskInstanceStatus.completed => 'مكتملة',
      };
}
