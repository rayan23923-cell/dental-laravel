import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/user_admin.dart';

final usersAdminRepositoryProvider = Provider<UsersAdminRepository>((ref) {
  return UsersAdminRepository(ref.watch(apiClientProvider));
});

/// `POST /users` (`permission:users,create`) — create-only, mirroring
/// `Api\UserController`. The new account's permissions and access scope
/// travel in the same request; changing them later is `permissions_admin`'s
/// job.
class UsersAdminRepository {
  UsersAdminRepository(this._client);
  final ApiClient _client;

  Future<UserFormOptions> formOptions() async {
    final data = await _client.getJson('/users/form-options') as Map<String, dynamic>;
    return UserFormOptions.fromJson(data);
  }

  Future<UserAdmin> create(Map<String, dynamic> payload) async {
    final data = await _client.postJson('/users', body: payload) as Map<String, dynamic>;
    return UserAdmin.fromJson(data['data'] as Map<String, dynamic>);
  }
}
