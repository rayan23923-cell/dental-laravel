import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/offline/local_json_store.dart';
import '../domain/case_sheet_sync_status.dart';

final caseSheetOfflineStoreProvider = Provider<CaseSheetOfflineStore>((ref) {
  return CaseSheetOfflineStore(ref.watch(localJsonStoreProvider));
});

/// One queued edit for a `(resource, id)` case-sheet record.
class PendingCaseSheetEdit {
  const PendingCaseSheetEdit({
    required this.resource,
    required this.id,
    required this.payload,
    required this.queuedAt,
    this.error,
  });

  factory PendingCaseSheetEdit.fromJson(Map<String, dynamic> json) => PendingCaseSheetEdit(
        resource: json['resource'] as String,
        id: json['id'] as int,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        queuedAt: DateTime.tryParse(json['queued_at'] as String? ?? '') ?? DateTime.now(),
        error: json['error'] as String?,
      );

  final String resource;
  final int id;
  final Map<String, dynamic> payload;
  final DateTime queuedAt;
  final String? error;

  Map<String, dynamic> toJson() => {
        'resource': resource,
        'id': id,
        'payload': payload,
        'queued_at': queuedAt.toIso8601String(),
        if (error != null) 'error': error,
      };
}

/// Local cache + offline edit queue for the 8 case-sheet resources — see
/// the "Offline mode for Flutter case sheets" plan for the overall design.
/// Every key is scoped under `offline_case_sheet_*` so `LocalJsonStore`'s
/// shared `shared_preferences` keyspace never collides with another
/// feature's own keys (e.g. `PrinterSettingsRepository`'s `printer_*`).
class CaseSheetOfflineStore {
  CaseSheetOfflineStore(this._store);
  final LocalJsonStore _store;

  static const _schemaPrefix = 'offline_case_sheet_schema::';
  static const _recordPrefix = 'offline_case_sheet_record::';
  static const _pendingPrefix = 'offline_case_sheet_pending::';
  static const _taskResolutionPrefix = 'offline_case_sheet_task::';

  // --- Schema cache (long-lived — schemas change rarely) ---

  Future<void> cacheSchema(String resource, Map<String, dynamic> schemaJson) {
    return _store.putJson('$_schemaPrefix$resource', schemaJson);
  }

  Future<Map<String, dynamic>?> readSchema(String resource) {
    return _store.getJson('$_schemaPrefix$resource');
  }

  // --- Record cache (write-through on every successful fetch/update) ---

  String _recordKey(String resource, int id) => '$_recordPrefix$resource::$id';

  Future<void> cacheRecord(String resource, int id, Map<String, dynamic> recordJson) {
    return _store.putJson(_recordKey(resource, id), recordJson);
  }

  Future<Map<String, dynamic>?> readRecord(String resource, int id) {
    return _store.getJson(_recordKey(resource, id));
  }

  // --- Task-instance -> (resource, recordId) resolution cache ---
  // Lets "مهامي" reach an already-visited case sheet's cached record while
  // offline, without needing `GET /task-instances/{id}/case-sheet` again.

  Future<void> cacheTaskResolution(int taskInstanceId, String resource, int? recordId) {
    return _store.putJson('$_taskResolutionPrefix$taskInstanceId', {
      'resource': resource,
      'record_id': recordId,
    });
  }

  Future<(String resource, int? recordId)?> readTaskResolution(int taskInstanceId) async {
    final json = await _store.getJson('$_taskResolutionPrefix$taskInstanceId');
    if (json == null) return null;
    return (json['resource'] as String, json['record_id'] as int?);
  }

  // --- Pending-edit queue — at most one entry per (resource, id) ---

  String _pendingKey(String resource, int id) => '$_pendingPrefix$resource::$id';

  Future<void> queueEdit(String resource, int id, Map<String, dynamic> payload) {
    return _store.putJson(
      _pendingKey(resource, id),
      PendingCaseSheetEdit(resource: resource, id: id, payload: payload, queuedAt: DateTime.now()).toJson(),
    );
  }

  Future<void> markEditFailed(String resource, int id, String message) async {
    final existing = await readPendingEdit(resource, id);
    if (existing == null) return; // synced/removed concurrently — nothing to mark
    await _store.putJson(
      _pendingKey(resource, id),
      PendingCaseSheetEdit(
        resource: resource,
        id: id,
        payload: existing.payload,
        queuedAt: existing.queuedAt,
        error: message,
      ).toJson(),
    );
  }

  Future<PendingCaseSheetEdit?> readPendingEdit(String resource, int id) async {
    final json = await _store.getJson(_pendingKey(resource, id));
    return json == null ? null : PendingCaseSheetEdit.fromJson(json);
  }

  Future<void> removePendingEdit(String resource, int id) {
    return _store.remove(_pendingKey(resource, id));
  }

  Future<List<PendingCaseSheetEdit>> listPendingEdits() async {
    final keys = await _store.keysWithPrefix(_pendingPrefix);
    final edits = <PendingCaseSheetEdit>[];
    for (final key in keys) {
      final json = await _store.getJson(key);
      if (json != null) edits.add(PendingCaseSheetEdit.fromJson(json));
    }
    return edits;
  }

  Future<CaseSheetSyncStatus> statusFor(String resource, int id) async {
    final pending = await readPendingEdit(resource, id);
    if (pending == null) return const CaseSheetSynced();
    return pending.error != null ? CaseSheetSyncFailed(pending.error!) : const CaseSheetSyncPending();
  }
}

final caseSheetPendingStatusProvider =
    FutureProvider.autoDispose.family<CaseSheetSyncStatus, (String resource, int id)>((ref, args) {
  return ref.watch(caseSheetOfflineStoreProvider).statusFor(args.$1, args.$2);
});
