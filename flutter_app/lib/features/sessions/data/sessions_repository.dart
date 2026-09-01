import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/account_session.dart';

final sessionsRepositoryProvider = Provider<SessionsRepository>((ref) {
  return SessionsRepository(ref.watch(apiClientProvider));
});

/// Talks to `Api\SessionController` — the current principal's own active
/// sessions (Sanctum tokens), Instagram-style device management.
class SessionsRepository {
  SessionsRepository(this._client);
  final ApiClient _client;

  Future<List<AccountSession>> list() async {
    final data = await _client.getJson('/sessions') as Map<String, dynamic>;
    return (data['data'] as List).map((e) => AccountSession.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> end(int id) {
    return _client.deleteJson('/sessions/$id');
  }

  Future<void> logoutAll() {
    return _client.postJson('/sessions/logout-all');
  }
}
