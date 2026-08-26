class BackupFile {
  const BackupFile({required this.name, required this.size, required this.mtime});

  factory BackupFile.fromJson(Map<String, dynamic> json) => BackupFile(
        name: json['name'] as String,
        size: json['size'] as int,
        // Unix seconds, matching `DatabaseBackupService::list()`'s
        // `Storage::lastModified()` (seconds, not the milliseconds
        // `DateTime.fromMillisecondsSinceEpoch` expects).
        mtime: DateTime.fromMillisecondsSinceEpoch((json['mtime'] as int) * 1000),
      );

  final String name;
  final int size;
  final DateTime mtime;
}

/// `Api\BackupController::status()`'s response shape. No download endpoint
/// here — matches the API's own scope (metadata only; the original web
/// UI's raw `.sql` download stays web-only, per that controller's
/// docblock).
class BackupStatus {
  const BackupStatus({required this.enabled, required this.lastBackupAt, required this.files});

  factory BackupStatus.fromJson(Map<String, dynamic> json) => BackupStatus(
        enabled: json['enabled'] as bool? ?? false,
        lastBackupAt: json['last_backup_at'] != null ? DateTime.tryParse(json['last_backup_at'] as String) : null,
        files: (json['files'] as List<dynamic>).map((e) => BackupFile.fromJson(e as Map<String, dynamic>)).toList(),
      );

  final bool enabled;
  final DateTime? lastBackupAt;
  final List<BackupFile> files;
}
