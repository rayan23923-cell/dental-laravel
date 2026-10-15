/// Mirrors `App\Http\Resources\AppNotificationResource` — a flat envelope
/// (`id`/`read_at`/`created_at`) plus whatever the originating notification's
/// `toArray()` put in `data` (today, only `App\Notifications\TaskAssigned`:
/// `title`/`message`/`task_instance_id`/`task_title`/`department`).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.readAt,
    required this.createdAt,
    required this.title,
    required this.message,
    required this.taskInstanceId,
    required this.taskTitle,
    required this.department,
    this.type,
    this.kind,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        readAt: json['read_at'] != null ? DateTime.tryParse(json['read_at'] as String) : null,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
        title: json['title'] as String? ?? '',
        message: json['message'] as String? ?? '',
        taskInstanceId: json['task_instance_id'] as int?,
        taskTitle: json['task_title'] as String?,
        department: json['department'] as String?,
        type: json['type'] as String?,
        kind: json['kind'] as String?,
      );

  final String id;
  final DateTime? readAt;
  final DateTime createdAt;
  final String title;
  final String message;
  final int? taskInstanceId;
  final String? taskTitle;
  final String? department;

  /// e.g. `task_assigned`, `photo_note`, `task_start_request` (2026-10-15).
  final String? type;
  final String? kind;

  bool get isUnread => readAt == null;
}
