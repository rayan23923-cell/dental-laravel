class ActivityLogEntry {
  const ActivityLogEntry({
    required this.id,
    required this.username,
    required this.userRole,
    required this.action,
    required this.module,
    required this.description,
    required this.createdAt,
  });

  factory ActivityLogEntry.fromJson(Map<String, dynamic> json) => ActivityLogEntry(
        id: json['id'] as int,
        username: json['username'] as String? ?? '',
        userRole: json['user_role'] as String? ?? '',
        action: json['action'] as String? ?? '',
        module: json['module'] as String? ?? '',
        description: json['description'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  final int id;
  final String username;
  final String userRole;
  final String action;
  final String module;
  final String description;
  final DateTime createdAt;
}
