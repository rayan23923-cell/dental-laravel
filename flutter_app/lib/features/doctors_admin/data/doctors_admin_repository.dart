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
}
