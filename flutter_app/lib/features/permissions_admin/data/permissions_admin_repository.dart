import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/permission_admin.dart';

final permissionsAdminRepositoryProvider = Provider<PermissionsAdminRepository>((ref) {
  return PermissionsAdminRepository(ref.watch(apiClientProvider));
});

/// `/permissions` — plain (non-`{data:}`-wrapped) JSON, matching
/// `Api\UserPermissionController`'s own shape.
class PermissionsAdminRepository {
  PermissionsAdminRepository(this._client);
  final ApiClient _client;

  Future<List<PermissionUser>> listUsers() async {
    final data = await _client.getJson('/permissions') as List<dynamic>;
    return data.map((e) => PermissionUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<PermissionsDetail> fetch(int userId) async {
    final data = await _client.getJson('/permissions/$userId') as Map<String, dynamic>;
    return PermissionsDetail.fromJson(data);
  }

  Future<void> update(int userId, List<String> grants) =>
      _client.putJson('/permissions/$userId', body: {'grants': grants});
}
