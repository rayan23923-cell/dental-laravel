import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/user_admin.dart';

final usersAdminRepositoryProvider = Provider<UsersAdminRepository>((ref) {
  return UsersAdminRepository(ref.watch(apiClientProvider));
});

/// `POST /users` (`permission:users,create`) — create-only, mirroring
/// `Api\UserController`. No list/edit/delete here: viewing existing users
/// and editing what they can do is `permissions_admin`'s job already;
/// this repository only exists to hand a freshly created user off to that
/// screen.
class UsersAdminRepository {
  UsersAdminRepository(this._client);
  final ApiClient _client;

  Future<UserAdmin> create(Map<String, dynamic> payload) async {
    final data = await _client.postJson('/users', body: payload) as Map<String, dynamic>;
    return UserAdmin.fromJson(data['data'] as Map<String, dynamic>);
  }
}
