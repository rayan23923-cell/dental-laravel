import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/case_sheet_type_admin.dart';

final caseSheetTypesAdminRepositoryProvider = Provider<CaseSheetTypesAdminRepository>((ref) {
  return CaseSheetTypesAdminRepository(ref.watch(apiClientProvider));
});

/// CRUD for `/case-sheet-types` — plain (non-`{data:}`-wrapped) JSON,
/// matching `Api\CaseSheetTypeController`'s own shape. Distinct from
/// `LookupRepository.caseSheetTypes()`, which fetches the same endpoint
/// but only for read-only dropdown use elsewhere (tasks admin); this
/// repository owns the write side.
class CaseSheetTypesAdminRepository {
  CaseSheetTypesAdminRepository(this._client);
  final ApiClient _client;

  Future<List<CaseSheetTypeAdmin>> list() async {
    final data = await _client.getJson('/case-sheet-types') as List<dynamic>;
    return data.map((e) => CaseSheetTypeAdmin.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CaseSheetTypeAdmin> create(Map<String, dynamic> payload) async {
    final data = await _client.postJson('/case-sheet-types', body: payload) as Map<String, dynamic>;
    return CaseSheetTypeAdmin.fromJson(data);
  }

  Future<CaseSheetTypeAdmin> update(int id, Map<String, dynamic> payload) async {
    final data = await _client.putJson('/case-sheet-types/$id', body: payload) as Map<String, dynamic>;
    return CaseSheetTypeAdmin.fromJson(data);
  }

  Future<void> delete(int id) => _client.deleteJson('/case-sheet-types/$id');
}
