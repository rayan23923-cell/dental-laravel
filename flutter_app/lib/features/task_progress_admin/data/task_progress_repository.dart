import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/nfc_lookup_result.dart';
import '../domain/task_progress_group.dart';

final taskProgressRepositoryProvider = Provider<TaskProgressRepository>((ref) {
  return TaskProgressRepository(ref.watch(apiClientProvider));
});

/// Talks to `Api\TaskProgressController` — both the original NFC-only
/// endpoints (`nfcScan`/`start`) and the fuller day/education-type/stage/
/// group/department/doctor matrix endpoints added alongside it, which
/// delegate server-side to the same `App\Services\TaskProgress*` classes
/// the web's `TaskProgressController` uses (see that controller's
/// docblock) — one shared implementation, two consumers.
class TaskProgressRepository {
  TaskProgressRepository(this._client);
  final ApiClient _client;

  Future<NfcLookupResult> nfcScan(String tagId) async {
    final data = await _client.postJson('/task-progress/nfc-scan', body: {'tag_id': tagId}) as Map<String, dynamic>;
    return NfcLookupResult.fromJson(data);
  }

  /// `patientRegistrationId` is required (2026-08-26) — identifies which
  /// patient this instance is for, so the server's `PatientScreeningGate`
  /// can refuse until that patient's screening is confirmed `clear`. See
  /// `task_progress_screen.dart::_startTask()` for the QR-scan step that
  /// obtains it.
  Future<TaskStartResult> start({
    required int doctorId,
    required int taskId,
    required int patientRegistrationId,
    String? notes,
  }) async {
    final response = await _client.postJson('/task-progress/start', body: {
      'doctor_id': doctorId,
      'task_id': taskId,
      'patient_registration_id': patientRegistrationId,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    }) as Map<String, dynamic>;
    return TaskStartResult.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<TaskProgressFilters> fetchFilters({String? day, int? educationTypeId, int? stageId}) async {
    final data = await _client.getJson('/task-progress/filters', query: {
      if (day != null) 'day': day,
      if (educationTypeId != null) 'education_type': educationTypeId,
      if (stageId != null) 'stage': stageId,
    }) as Map<String, dynamic>;
    return TaskProgressFilters.fromJson(data);
  }

  Future<TaskProgressGroupDetail> fetchGroup(int groupId) async {
    final data = await _client.getJson('/task-progress/groups/$groupId') as Map<String, dynamic>;
    return TaskProgressGroupDetail.fromJson(data);
  }

  Future<void> completeInstance(int instanceId, {double? grade, String? notes}) {
    return _client.putJson('/task-progress/instances/$instanceId/complete', body: {'grade': grade, 'notes': notes});
  }

  Future<void> updateInstance(int instanceId, {double? grade, String? notes}) {
    return _client.putJson('/task-progress/instances/$instanceId', body: {'grade': grade, 'notes': notes});
  }
}
