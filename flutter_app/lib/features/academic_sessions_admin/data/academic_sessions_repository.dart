import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/academic_session_selection.dart';
import '../domain/academic_session_admin.dart';

final academicSessionsRepositoryProvider = Provider<AcademicSessionsRepository>((ref) {
  return AcademicSessionsRepository(ref.watch(apiClientProvider), ref.watch(academicSessionSelectionProvider));
});

/// CRUD for `/academic-sessions` plus `set-current` — plain (non-`{data:}`-
/// wrapped) JSON, matching `Api\AcademicSessionController`'s own shape.
/// `select()` (2026-10-17) is the web's "view this year": the server
/// checks the choice, and [AcademicSessionSelection] keeps it so every
/// later request carries it (Sanctum is stateless).
class AcademicSessionsRepository {
  AcademicSessionsRepository(this._client, this._selection);
  final ApiClient _client;
  final AcademicSessionSelection _selection;

  Future<List<AcademicSessionAdmin>> list() async {
    final data = await _client.getJson('/academic-sessions') as List<dynamic>;
    return data.map((e) => AcademicSessionAdmin.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AcademicSessionDetail> fetch(int id) async {
    final data = await _client.getJson('/academic-sessions/$id') as Map<String, dynamic>;
    return AcademicSessionDetail.fromJson(data);
  }

  Future<AcademicSessionAdmin> create(Map<String, dynamic> payload) async {
    final data = await _client.postJson('/academic-sessions', body: payload) as Map<String, dynamic>;
    return AcademicSessionAdmin.fromJson(data);
  }

  Future<AcademicSessionAdmin> update(int id, Map<String, dynamic> payload) async {
    final data = await _client.putJson('/academic-sessions/$id', body: payload) as Map<String, dynamic>;
    return AcademicSessionAdmin.fromJson(data);
  }

  Future<void> delete(int id) => _client.deleteJson('/academic-sessions/$id');

  Future<AcademicSessionAdmin> setCurrent(int id) async {
    final data = await _client.putJson('/academic-sessions/$id/set-current') as Map<String, dynamic>;
    return AcademicSessionAdmin.fromJson(data);
  }

  /// `null` when no academic year is currently active — same "branding is
  /// an enhancement, never blocks" contract as `clinicSettingsProvider`,
  /// since this only ever feeds a small display banner.
  Future<CurrentAcademicYear?> current() async {
    final data = await _client.getJson('/academic-sessions/current');
    return data == null ? null : CurrentAcademicYear.fromJson(data as Map<String, dynamic>);
  }

  /// View [id]'s year from now on (the web's `academic-sessions.select`).
  Future<CurrentAcademicYear> select(int id) async {
    final data = await _client.postJson('/academic-sessions/select', body: {'academic_session_id': id}) as Map<String, dynamic>;
    await _selection.write(id);
    return CurrentAcademicYear.fromJson(data);
  }
}
