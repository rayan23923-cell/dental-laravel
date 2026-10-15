import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/paginated.dart';
import 'case_sheet_offline_store.dart';

final caseSheetRecordRepositoryProvider = Provider<CaseSheetRecordRepository>((ref) {
  return CaseSheetRecordRepository(ref.watch(apiClientProvider), ref.watch(caseSheetOfflineStoreProvider));
});

/// Generic CRUD against any of the 8 case-sheet REST resources
/// (`/api/v1/{resource}`) — they're all standard `apiResource` controllers
/// with the same `{data: {...}}` / paginated-`{data: [...]}` envelope, so
/// one repository parametrized by resource name covers all 8 instead of 8
/// near-identical classes.
///
/// Also the offline layer for the same 8 resources (see "Offline mode for
/// Flutter case sheets" — `docs/case-sheets-and-clinical-charting.md`):
/// `fetch()`/`openFor()` write-through cache on success and fall back to
/// the cache on a pure connectivity failure; `update()` queues the edit
/// locally on the same failure instead of throwing. A real rejection
/// (422/403/etc., anything that isn't [NetworkException]) still throws
/// normally in every method — only "the network itself is unreachable"
/// gets the offline treatment, never an actual error response.
class CaseSheetRecordRepository {
  CaseSheetRecordRepository(this._client, this._offline);
  final ApiClient _client;
  final CaseSheetOfflineStore _offline;

  Future<Paginated<Map<String, dynamic>>> list(String resource, {String? doctorId}) async {
    final data = await _client.getJson('/$resource') as Map<String, dynamic>;
    return Paginated.fromJson(data, (json) => json);
  }

  Future<Map<String, dynamic>> fetch(String resource, int id) async {
    try {
      final data = await _client.getJson('/$resource/$id') as Map<String, dynamic>;
      final record = data['data'] as Map<String, dynamic>;
      await _offline.cacheRecord(resource, id, record);
      return record;
    } on NetworkException {
      final cached = await _offline.readRecord(resource, id);
      if (cached != null) return cached;
      rethrow; // never seen this record before — nothing to fall back to
    }
  }

  Future<Map<String, dynamic>> create(String resource, Map<String, dynamic> payload) async {
    final data = await _client.postJson('/$resource', body: payload) as Map<String, dynamic>;
    return data['data'] as Map<String, dynamic>;
  }

  /// The real network write — throws normally on any failure, including a
  /// pure connectivity one. [update] (below) is what screens call; this is
  /// what [CaseSheetSyncService] calls, since syncing a queued edit needs
  /// to actually distinguish "reached the server and it rejected this" (stop
  /// retrying, surface the error) from "still offline" (leave it queued) —
  /// a distinction [update]'s own catch-and-queue behavior deliberately
  /// erases for its own (screen-facing) callers.
  /// Saves one stage date or grade the moment it changes (2026-10-15) —
  /// `PATCH /{resource}/{id}/stage-field` with exactly that one column.
  Future<void> saveStageField(String resource, int id, String key, String? value) async {
    await _client.patchJson('/$resource/$id/stage-field', body: {key: value});
  }

  Future<Map<String, dynamic>> updateRemote(String resource, int id, Map<String, dynamic> payload) async {
    final data = await _client.putJson('/$resource/$id', body: payload) as Map<String, dynamic>;
    return data['data'] as Map<String, dynamic>;
  }

  /// Partial update — only send the keys the form actually edited (every
  /// `update()` on these 8 controllers validates with `sometimes`, so an
  /// omitted key is left untouched server-side, never nulled).
  ///
  /// Offline: a [NetworkException] here never propagates to the caller —
  /// the payload is merged into the locally cached record (so re-reading
  /// this same record reflects the edit even before it syncs) and queued
  /// via [CaseSheetOfflineStore.queueEdit], returning the merged record so
  /// the screen's existing success path (snackbar, navigation) is
  /// unaffected. Any other failure (a real 403/422/etc.) still throws.
  Future<Map<String, dynamic>> update(String resource, int id, Map<String, dynamic> payload) async {
    try {
      final record = await updateRemote(resource, id, payload);
      await _offline.removePendingEdit(resource, id);
      await _offline.cacheRecord(resource, id, record);
      return record;
    } on NetworkException {
      final cached = await _offline.readRecord(resource, id) ?? <String, dynamic>{};
      final merged = {...cached, ...payload};
      await _offline.cacheRecord(resource, id, merged);
      await _offline.queueEdit(resource, id, payload);
      return merged;
    }
  }

  /// Flutter's entry point into the same task-instance → clinical-form
  /// linkage the web has had all along (`CaseSheetController::open()`) —
  /// added 2026-08-27, since this repository's `create()` never carried a
  /// `task_instances_id` before. Resolves which of the 8 resources this
  /// case's task uses, and whether a record already exists for it.
  Future<CaseSheetOpenResult> openFor(int taskInstanceId) async {
    try {
      final data = await _client.getJson('/task-instances/$taskInstanceId/case-sheet') as Map<String, dynamic>;
      final resource = data['resource'] as String;
      final recordId = data['record_id'] as int?;
      await _offline.cacheTaskResolution(taskInstanceId, resource, recordId);
      return CaseSheetOpenResult(
        resource: resource,
        recordId: recordId,
        readonly: data['readonly'] as bool? ?? false,
        supervisorEditableFields: (data['supervisor_editable_fields'] as List<dynamic>?)?.cast<String>() ?? const [],
        // Auto-fills a brand-new sheet's patient fields from whichever
        // patient TaskStarter::start() already tied this task instance
        // to (2026-09-02) — see Api\CaseSheetController::open()'s own doc
        // comment. Empty when a record already exists (nothing to
        // prefill) or this task instance somehow has no linked patient.
        patientPrefill: (data['patient_prefill'] as Map<String, dynamic>?) ?? const {},
      );
    } on NetworkException {
      final cached = await _offline.readTaskResolution(taskInstanceId);
      if (cached == null) rethrow;
      // A cached resolution only ever came from a doctor's own successful
      // `openFor()` call (never a staff preview — see `openForTask`'s own
      // doc comment on the API side), so `readonly`/`supervisorEditableFields`
      // are safe to default here the same way `openForTask` always does.
      // `patientPrefill` isn't cached — a genuinely offline-first create
      // (never seen online before) has nothing to prefill from anyway,
      // and re-opening a since-created record instead reads the prefilled
      // values back from its own cached record, not from here.
      return CaseSheetOpenResult(resource: cached.$1, recordId: cached.$2);
    }
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

  /// `Api\CaseSheetPrintController::show()`'s response — the *rendered
  /// document model* (letterhead fields, sections already resolved to
  /// label/value cells, chart grids, stage rows), not the raw record. No
  /// `{data: ...}` envelope, unlike every other method here — that
  /// controller returns the document fields at the top level.
  Future<Map<String, dynamic>> fetchPrintDocument(String resource, int id) async {
    return await _client.getJson('/case-sheet-prints/$resource/$id') as Map<String, dynamic>;
  }
}

class CaseSheetOpenResult {
  const CaseSheetOpenResult({
    required this.resource,
    required this.recordId,
    this.readonly = false,
    this.supervisorEditableFields = const [],
    this.patientPrefill = const {},
  });
  final String resource;
  final int? recordId;

  /// Patient fields to seed a brand-new record with — only ever non-empty
  /// when [recordId] is null (see [openFor]'s own doc comment).
  final Map<String, dynamic> patientPrefill;

  /// Set only by [openFor] — a staff viewer previewing an existing case
  /// (see `Api\CaseSheetController::open()`'s `readonly`). Always false
  /// from [openForTask], which is doctor-only by design.
  final bool readonly;

  /// This viewer's own supervisor-editable fields for [resource] — see
  /// `App\Support\CaseSheetSupervisorFields`. Empty for a doctor.
  final List<String> supervisorEditableFields;
}
