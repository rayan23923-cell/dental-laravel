import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';
import '../domain/doctor_admin.dart';

final doctorsAdminRepositoryProvider = Provider<DoctorsAdminRepository>((ref) {
  return DoctorsAdminRepository(ref.watch(apiClientProvider));
});

/// CRUD for `/doctors` (staff-only, `permission:doctors,*`). Profile-image
/// upload (`multipart`, the one field the API also accepts on this
/// resource) isn't wired up yet — every other field is — same
/// "incrementally after" scope already used elsewhere in this app rather
/// than guessing at a multipart/`_method`-spoofing flow with nothing in
/// the codebase yet to model it on (the "photo via image_picker" line in
/// this README's own Phase 1 plan was never actually built, confirmed by
/// grepping the codebase before writing this — not left unbuilt twice on
/// an assumption). Education-type/stage dropdown options come from
/// `core/data/lookup_repository.dart` now, shared with every other
/// feature that needs the same reference data.
class DoctorsAdminRepository {
  DoctorsAdminRepository(this._client);
  final ApiClient _client;

  Future<Paginated<DoctorAdmin>> list({String? search, int? educationTypeId, int? stageId}) async {
    final data = await _client.getJson('/doctors', query: {
      if (search != null && search.isNotEmpty) 'search': search,
      if (educationTypeId != null) 'education_type_id': educationTypeId,
      if (stageId != null) 'stage_id': stageId,
    }) as Map<String, dynamic>;
    return Paginated.fromJson(data, DoctorAdmin.fromJson);
  }

  Future<DoctorAdmin> fetch(int id) async {
    final data = await _client.getJson('/doctors/$id') as Map<String, dynamic>;
    return DoctorAdmin.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<DoctorAdmin> create(Map<String, dynamic> payload) async {
    final data = await _client.postJson('/doctors', body: payload) as Map<String, dynamic>;
    return DoctorAdmin.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<DoctorAdmin> update(int id, Map<String, dynamic> payload) async {
    final data = await _client.putJson('/doctors/$id', body: payload) as Map<String, dynamic>;
    return DoctorAdmin.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<void> delete(int id) => _client.deleteJson('/doctors/$id');

  /// Archive several doctors (`DELETE /doctors-bulk`, the web's "حذف
  /// المحدد"): linked doctors are skipped and named in `blocked`.
  Future<({int archived, List<String> blocked})> deleteMany(List<int> ids) async {
    final data = await _client.deleteJsonData('/doctors-bulk', body: {'ids': ids}) as Map<String, dynamic>;
    return (
      archived: (data['archived'] as num?)?.toInt() ?? 0,
      blocked: [for (final b in data['blocked'] as List<dynamic>? ?? const []) b.toString()],
    );
  }

  /// The empty import sheet (`GET /doctors-template`), as .xlsx bytes.
  Future<List<int>> template() => _client.getBytes('/doctors-template');

  /// Every doctor as .xlsx (`GET /doctors-export`), narrowed to an
  /// education type/stage like the web's export.
  Future<List<int>> export({int? educationTypeId, int? stageId}) => _client.getBytes('/doctors-export', query: {
        if (educationTypeId != null) 'education_type_id': educationTypeId,
        if (stageId != null) 'stage_id': stageId,
      });

  /// Excel import (`POST /doctors-import`): every row gets the same
  /// education type, stage and (optional) default password.
  Future<({int imported, int skipped, int emailsQueued})> import({
    required List<int> bytes,
    required String fileName,
    required int educationTypeId,
    required int stageId,
    String? defaultPassword,
  }) async {
    final data = await _client.postFile(
      '/doctors-import',
      formData: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: fileName),
        'education_type_id': educationTypeId,
        'stage_id': stageId,
        if (defaultPassword != null && defaultPassword.isNotEmpty) 'default_password': defaultPassword,
      }),
    ) as Map<String, dynamic>;
    return (
      imported: (data['imported'] as num?)?.toInt() ?? 0,
      skipped: (data['skipped'] as num?)?.toInt() ?? 0,
      emailsQueued: (data['emails_queued'] as num?)?.toInt() ?? 0,
    );
  }
}
