import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';

final caseSheetRecordRepositoryProvider = Provider<CaseSheetRecordRepository>((ref) {
  return CaseSheetRecordRepository(ref.watch(apiClientProvider));
});

/// Generic CRUD against any of the 8 case-sheet REST resources
/// (`/api/v1/{resource}`) — they're all standard `apiResource` controllers
/// with the same `{data: {...}}` / paginated-`{data: [...]}` envelope, so
/// one repository parametrized by resource name covers all 8 instead of 8
/// near-identical classes.
class CaseSheetRecordRepository {
  CaseSheetRecordRepository(this._client);
  final ApiClient _client;

  Future<Paginated<Map<String, dynamic>>> list(String resource, {String? doctorId}) async {
    final data = await _client.getJson('/$resource') as Map<String, dynamic>;
    return Paginated.fromJson(data, (json) => json);
  }

  Future<Map<String, dynamic>> fetch(String resource, int id) async {
    final data = await _client.getJson('/$resource/$id') as Map<String, dynamic>;
    return data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> create(String resource, Map<String, dynamic> payload) async {
    final data = await _client.postJson('/$resource', body: payload) as Map<String, dynamic>;
    return data['data'] as Map<String, dynamic>;
  }

  /// Partial update — only send the keys the form actually edited (every
  /// `update()` on these 8 controllers validates with `sometimes`, so an
  /// omitted key is left untouched server-side, never nulled).
  Future<Map<String, dynamic>> update(String resource, int id, Map<String, dynamic> payload) async {
    final data = await _client.putJson('/$resource/$id', body: payload) as Map<String, dynamic>;
    return data['data'] as Map<String, dynamic>;
  }

  /// Flutter's entry point into the same task-instance → clinical-form
  /// linkage the web has had all along (`CaseSheetController::open()`) —
  /// added 2026-08-27, since this repository's `create()` never carried a
  /// `task_instances_id` before. Resolves which of the 8 resources this
  /// case's task uses, and whether a record already exists for it.
  Future<CaseSheetOpenResult> openFor(int taskInstanceId) async {
    final data = await _client.getJson('/task-instances/$taskInstanceId/case-sheet') as Map<String, dynamic>;
    return CaseSheetOpenResult(
      resource: data['resource'] as String,
      recordId: data['record_id'] as int?,
    );
  }

  /// The optional pre-instance draft (2026-08-28) — same shape as [openFor],
  /// but for a not-yet-started slot: no `TaskInstance` exists yet, so this
  /// resolves/creates a draft keyed by (doctor, task) instead. See
  /// `Api\CaseSheetController::openForTask()`'s doc comment for why this
  /// deliberately never creates a real task instance.
  Future<CaseSheetOpenResult> openForTask(int taskId) async {
    final data = await _client.getJson('/tasks/$taskId/case-sheet-draft') as Map<String, dynamic>;
    return CaseSheetOpenResult(
      resource: data['resource'] as String,
      recordId: data['record_id'] as int?,
    );
  }
}

class CaseSheetOpenResult {
  const CaseSheetOpenResult({required this.resource, required this.recordId});
  final String resource;
  final int? recordId;
}
