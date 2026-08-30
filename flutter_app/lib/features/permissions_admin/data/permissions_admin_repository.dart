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

  /// `scope` lists follow the same "empty = unrestricted" convention as the
  /// web form: omitting a dimension and sending `[]` for it both resolve to
  /// unrestricted server-side (`ScopeHelper`'s zero-rows rule), so this
  /// always sends the four keys rather than trying to distinguish them.
  Future<void> update(int userId, List<String> grants, PermissionScopeSelection scope) => _client.putJson(
        '/permissions/$userId',
        body: {
          'grants': grants,
          'scope': {
            'departments': scope.departmentIds,
            'stages': scope.stageIds,
            'education_types': scope.educationTypeIds,
            'academic_sessions': scope.academicSessionIds,
          },
        },
      );
}
