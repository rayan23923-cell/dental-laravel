/// Mirrors `Api\TaskProgressController::nfcScan()`'s two response shapes —
/// `kind: 'doctor'` (identified, no unambiguous pending task) or
/// `kind: 'pending_task'` (identified + exactly one candidate task, offered
/// as a direct start shortcut). See that controller's docblock for the
/// "unambiguous" definition (`App\Support\PendingTaskFinder`).
class NfcLookupDoctor {
  const NfcLookupDoctor({required this.id, required this.name, required this.username});

  factory NfcLookupDoctor.fromJson(Map<String, dynamic> json) => NfcLookupDoctor(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        username: json['username'] as String? ?? '',
      );

  final int id;
  final String name;
  final String username;
}

class NfcLookupTask {
  const NfcLookupTask({required this.id, required this.title, required this.department, required this.requiredCount});

  factory NfcLookupTask.fromJson(Map<String, dynamic> json) => NfcLookupTask(
        id: json['id'] as int,
        title: json['title'] as String? ?? '',
        department: json['department'] as String?,
        requiredCount: json['required_count'] as int?,
      );

  final int id;
  final String title;
  final String? department;
  final int? requiredCount;
}

class NfcLookupResult {
  const NfcLookupResult({required this.kind, required this.doctor, this.task});

  factory NfcLookupResult.fromJson(Map<String, dynamic> json) => NfcLookupResult(
        kind: json['kind'] as String,
        doctor: NfcLookupDoctor.fromJson(json['doctor'] as Map<String, dynamic>),
        task: json['task'] != null ? NfcLookupTask.fromJson(json['task'] as Map<String, dynamic>) : null,
      );

  final String kind;
  final NfcLookupDoctor doctor;
  final NfcLookupTask? task;

  bool get hasPendingTask => kind == 'pending_task' && task != null;
}
