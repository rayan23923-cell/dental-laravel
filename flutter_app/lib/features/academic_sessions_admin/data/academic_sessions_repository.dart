import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/academic_session_admin.dart';

final academicSessionsRepositoryProvider = Provider<AcademicSessionsRepository>((ref) {
  return AcademicSessionsRepository(ref.watch(apiClientProvider));
});

/// CRUD for `/academic-sessions` plus `set-current` — plain (non-`{data:}`-
/// wrapped) JSON, matching `Api\AcademicSessionController`'s own shape.
/// `select()` (which session a *web* browser session is currently
/// "viewing") is deliberately not ported — Sanctum is stateless, so it has
/// no equivalent here, per the controller's own docblock.
class AcademicSessionsRepository {
  AcademicSessionsRepository(this._client);
  final ApiClient _client;

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
}
