import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/group_admin.dart';

final groupsAdminRepositoryProvider = Provider<GroupsAdminRepository>((ref) {
  return GroupsAdminRepository(ref.watch(apiClientProvider));
});

/// CRUD for `/groups` plus its two membership endpoints — all plain
/// (non-`{data:}`-wrapped) JSON, matching `Api\GroupController`'s own
/// shape (`response()->json($group)`/`response()->json($groups)`, no
/// Resource class), not the REST-envelope convention most of this API
/// uses.
class GroupsAdminRepository {
  GroupsAdminRepository(this._client);
  final ApiClient _client;

  Future<List<GroupAdmin>> list({String? search, int? stageId, int? doctorId}) async {
    final data = await _client.getJson('/groups', query: {
      if (search != null && search.isNotEmpty) 'search': search,
      if (stageId != null) 'stage_id': stageId,
      if (doctorId != null) 'doctor_id': doctorId,
    }) as List<dynamic>;
    return data.map((e) => GroupAdmin.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<GroupAdmin> fetch(int id) async {
    final data = await _client.getJson('/groups/$id') as Map<String, dynamic>;
    return GroupAdmin.fromJson(data);
  }

  Future<GroupAdmin> create(Map<String, dynamic> payload) async {
    final data = await _client.postJson('/groups', body: payload) as Map<String, dynamic>;
    return GroupAdmin.fromJson(data);
  }

  Future<GroupAdmin> update(int id, Map<String, dynamic> payload) async {
    final data = await _client.putJson('/groups/$id', body: payload) as Map<String, dynamic>;
    return GroupAdmin.fromJson(data);
  }

  Future<void> delete(int id) => _client.deleteJson('/groups/$id');

  Future<List<AvailableDoctor>> availableDoctors({int? stageId}) async {
    final data = await _client.getJson('/groups-available-doctors', query: {if (stageId != null) 'stage_id': stageId})
        as List<dynamic>;
    return data.map((e) => AvailableDoctor.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> addDoctors(int groupId, List<int> doctorIds) =>
      _client.postJson('/groups/$groupId/doctors', body: {'doctor_ids': doctorIds});

  Future<void> removeDoctors(int groupId, List<int> doctorIds) =>
      _client.deleteJson('/groups/$groupId/doctors', body: {'doctor_ids': doctorIds});
}
