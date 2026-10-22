import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/user_admin.dart';

final usersAdminRepositoryProvider = Provider<UsersAdminRepository>((ref) {
  return UsersAdminRepository(ref.watch(apiClientProvider));
});

/// `/users` — mirrors `Api\UserController`: `POST` (`permission:users,create`)
/// creates an account with its permissions and access scope; the rest is
/// users management (2026-10-21, by request): list (`users,view`), and
/// edit details / change the password (`users,edit`). Changing permissions
/// later is `permissions_admin`'s job.
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

  Future<List<ManagedUser>> list() async {
    final data = await _client.getJson('/users') as List<dynamic>;
    return data.map((e) => ManagedUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ManagedUser> fetch(int id) async {
    final data = await _client.getJson('/users/$id') as Map<String, dynamic>;
    return ManagedUser.fromJson(data);
  }

  Future<void> update(int id, Map<String, dynamic> payload) => _client.putJson('/users/$id', body: payload);

  /// Returns the generated password (shown once) when [generate] is set.
  Future<({String? password, bool emailed})> changePassword(
    int id, {
    String? password,
    bool generate = false,
    bool sendEmail = false,
  }) async {
    final data = await _client.putJson('/users/$id/password', body: {
      if (!generate) 'password': password,
      if (!generate) 'password_confirmation': password,
      'generate': generate,
      'send_email': sendEmail,
    }) as Map<String, dynamic>;
    return (password: data['password'] as String?, emailed: data['emailed'] as bool? ?? false);
  }
}
