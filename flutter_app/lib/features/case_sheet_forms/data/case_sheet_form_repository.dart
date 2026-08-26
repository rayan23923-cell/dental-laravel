import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/case_sheet_form_schema.dart';

final caseSheetFormRepositoryProvider = Provider<CaseSheetFormRepository>((ref) {
  return CaseSheetFormRepository(ref.watch(apiClientProvider));
});

class CaseSheetFormRepository {
  CaseSheetFormRepository(this._client);
  final ApiClient _client;

  Future<CaseSheetFormSchema> fetch(String resource) async {
    final data = await _client.getJson('/case-sheet-forms/$resource') as Map<String, dynamic>;
    return CaseSheetFormSchema.fromJson(data);
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
