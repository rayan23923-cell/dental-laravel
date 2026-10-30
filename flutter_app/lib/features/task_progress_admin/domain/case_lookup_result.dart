import 'nfc_lookup_result.dart';
import 'task_progress_group.dart';

/// `POST /task-progress/lookup` (2026-10-30): what a scanned case QR or a
/// typed case code points at — see `App\Services\TaskCodeLookup`.
/// `kind` is `task_instance` (a started case), `pending_task` (a task the
/// doctor hasn't started yet) or `doctor` (an ID card QR).
class CaseLookupResult {
  const CaseLookupResult({
    required this.kind,
    required this.doctor,
    this.taskId,
    this.taskTitle,
    this.department,
    this.caseSheet,
    this.instanceId,
    this.card,
    this.group,
    this.code,
  });

  factory CaseLookupResult.fromJson(Map<String, dynamic> json) {
    final task = json['task'] as Map<String, dynamic>?;
    final doctor = json['doctor'] as Map<String, dynamic>;
    return CaseLookupResult(
      kind: json['kind'] as String,
      doctor: NfcLookupDoctor.fromJson({...doctor, 'id': doctor['id'] ?? 0}),
      taskId: task?['id'] as int?,
      taskTitle: task?['title'] as String?,
      department: task?['department'] as String?,
      caseSheet: task?['case_sheet'] as String?,
      instanceId: json['instance_id'] as int?,
      card: json['card'] is Map<String, dynamic> ? TaskSlotCard.fromJson(json['card'] as Map<String, dynamic>) : null,
      group: json['group'] is Map<String, dynamic> ? TaskProgressGroupOption.fromJson(json['group'] as Map<String, dynamic>) : null,
      code: json['code'] as String?,
    );
  }

  final String kind;
  final NfcLookupDoctor doctor;
  final int? taskId;
  final String? taskTitle;
  final String? department;
  final String? caseSheet;
  final int? instanceId;

  /// The task progress slot card this case is (or, for a task not started
  /// yet, the next free slot); null once no slot is left to start.
  final TaskSlotCard? card;

  /// The doctor's group, stage and education type, for the start receipt.
  final TaskProgressGroupOption? group;

  /// The typeable code, used to look the case up again after an action.
  final String? code;

  bool get isDoctorCard => kind == 'doctor';
}
