import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';

final lookupRepositoryProvider = Provider<LookupRepository>((ref) {
  return LookupRepository(ref.watch(apiClientProvider));
});

/// `{id, name}` — the shape every simple reference-data lookup shares.
///
/// [stageId]/[educationTypeId] are additive, nullable, and only populated
/// for `stages()`/`departments()` (the API already returns them —
/// `Api\LookupController::stages()`/`departments()` — this was just never
/// read). Needed for client-side cascading filters (education type ->
/// stage -> department), the same shape `Doctors/Create.vue` already
/// filters on for the web. Every other caller of `LookupItem` (Patients,
/// Doctors, Appointments admin) is unaffected — the fields are simply
/// null for endpoints that don't return them.
///
/// [stageName]/[educationTypeName] are a second, separate additive pair —
/// only populated for `tasks()` (`TaskResource`'s nested `stage.education_type`)
/// — for the patient-registration "التشخيص" picker's informational
/// stage/education-type line, mirroring what the web reads straight off
/// its own `tasks` Inertia prop.
class LookupItem {
  const LookupItem({
    required this.id,
    required this.name,
    this.stageId,
    this.educationTypeId,
    this.stageName,
    this.educationTypeName,
  });

  factory LookupItem.fromJson(Map<String, dynamic> json) {
    final stage = json['stage'] as Map<String, dynamic>?;
    final educationType = stage?['education_type'] as Map<String, dynamic>?;
    return LookupItem(
      id: json['id'] as int,
      name: (json['name'] ?? json['title'] ?? json['name_ar']) as String? ?? '',
      stageId: (json['stage_id'] ?? stage?['id']) as int?,
      educationTypeId: json['education_type_id'] as int?,
      stageName: stage?['name'] as String?,
      educationTypeName: educationType?['name'] as String?,
    );
  }

  final int id;
  final String name;
  final int? stageId;
  final int? educationTypeId;
  final String? stageName;
  final String? educationTypeName;
}

/// Read-only reference-data fetches (`Api\LookupController`'s `GET`
/// endpoints, `Api\CaseSheetTypeController::index()`,
/// `Api\TaskController::index()`) shared across every feature that needs
/// a dropdown populated from one of them — pulled out once a 3rd/4th
/// consumer (patients' stage picker, doctors' education-type+stage
/// pickers, appointments' task picker, now tasks admin's
/// department/stage/case-sheet-type pickers) made duplicating each fetch
/// per-feature clearly not worth it anymore. Each of those features' own
/// repository still owns its *writes* (patients, doctors, tasks, …) —
/// this is only for the read side they all shared.
class LookupRepository {
  LookupRepository(this._client);
  final ApiClient _client;

  Future<List<LookupItem>> educationTypes() async {
    final data = await _client.getJson('/education-types') as List<dynamic>;
    return data.map((e) => LookupItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<LookupItem>> stages() async {
    final data = await _client.getJson('/stages') as List<dynamic>;
    return data.map((e) => LookupItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<LookupItem>> departments() async {
    final data = await _client.getJson('/departments') as List<dynamic>;
    return data.map((e) => LookupItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<LookupItem>> caseSheetTypes() async {
    final data = await _client.getJson('/case-sheet-types') as List<dynamic>;
    return data.map((e) => LookupItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `Api\TaskController::index()` hardcodes `paginate(15)`, ignoring any
  /// `per_page` override — fetched page by page since this is a dropdown
  /// source that needs every row, not just page 1 (see
  /// `RecordsRepository`'s original version of this same method, now
  /// moved here).
  Future<List<LookupItem>> tasks() async {
    final items = <LookupItem>[];
    var page = 1;
    while (true) {
      final data = await _client.getJson('/tasks', query: {'page': page}) as Map<String, dynamic>;
      final rows = (data['data'] as List<dynamic>).map((e) => LookupItem.fromJson(e as Map<String, dynamic>)).toList();
      items.addAll(rows);
      final meta = data['meta'] as Map<String, dynamic>?;
      final currentPage = meta?['current_page'] as int? ?? 1;
      final lastPage = meta?['last_page'] as int? ?? 1;
      if (currentPage >= lastPage) break;
      page++;
    }
    return items;
  }

  /// Resolves a scanned NFC tag (`NfcUidReader.readUid()`) to the doctor
  /// it's linked to — `Api\DoctorController::nfcLookup()`, shared between
  /// the doctors and groups admin list screens' search boxes (tap-to-scan
  /// instead of typing a name). Reuses `LookupItem` as-is: the response is
  /// a full `DoctorResource`, but its `id`/`name`/`stage_id`/
  /// `education_type_id` fields are exactly the ones `LookupItem.fromJson`
  /// already reads — no new class needed. Throws `ApiException` (404,
  /// "لا يوجد طبيب مرتبط بهذه البطاقة") if the tag isn't linked to anyone,
  /// same shape as `TaskProgressController::nfcScan()`'s.
  Future<LookupItem> doctorByNfcTag(String tagId) async {
    final data = await _client.getJson('/doctors-nfc-lookup', query: {'tag_id': tagId}) as Map<String, dynamic>;
    return LookupItem.fromJson(data['data'] as Map<String, dynamic>);
  }
}
