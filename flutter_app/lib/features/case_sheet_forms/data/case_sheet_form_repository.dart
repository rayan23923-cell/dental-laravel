import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/case_sheet_form_schema.dart';
import 'case_sheet_offline_store.dart';

final caseSheetFormRepositoryProvider = Provider<CaseSheetFormRepository>((ref) {
  return CaseSheetFormRepository(ref.watch(apiClientProvider), ref.watch(caseSheetOfflineStoreProvider));
});

class CaseSheetFormRepository {
  CaseSheetFormRepository(this._client, this._offline);
  final ApiClient _client;
  final CaseSheetOfflineStore _offline;

  /// A resource's layout schema changes rarely (it's a PHP `sections()`
  /// definition, not per-record data), so this is a plain long-lived
  /// write-through cache — same fallback shape as
  /// `CaseSheetRecordRepository.fetch()`.
  Future<CaseSheetFormSchema> fetch(String resource) async {
    try {
      final data = await _client.getJson('/case-sheet-forms/$resource') as Map<String, dynamic>;
      await _offline.cacheSchema(resource, data);
      return CaseSheetFormSchema.fromJson(data);
    } on NetworkException {
      final cached = await _offline.readSchema(resource);
      if (cached != null) return CaseSheetFormSchema.fromJson(cached);
      rethrow;
    }
  }

  /// The 8 case-sheet resources (`Api\CaseSheetFormController::index()`),
  /// each `{resource, title}` — drives the "pick a sheet type" list.
  Future<List<(String resource, String title)>> listResources() async {
    final data = await _client.getJson('/case-sheet-forms') as Map<String, dynamic>;
    return (data['data'] as List)
        .cast<Map<String, dynamic>>()
        .map((e) => (e['resource'] as String, e['title'] as String))
        .toList();
  }
}
