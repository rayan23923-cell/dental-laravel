import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/backup_status.dart';

final backupAdminRepositoryProvider = Provider<BackupAdminRepository>((ref) {
  return BackupAdminRepository(ref.watch(apiClientProvider));
});

/// `/backup` — plain (non-`{data:}`-wrapped) JSON, matching
/// `Api\BackupController`'s own shape.
class BackupAdminRepository {
  BackupAdminRepository(this._client);
  final ApiClient _client;

  Future<BackupStatus> fetch() async {
    final data = await _client.getJson('/backup') as Map<String, dynamic>;
    return BackupStatus.fromJson(data);
  }

  Future<void> createBackup() => _client.postJson('/backup');

  Future<void> setAutoEnabled(bool enabled) => _client.putJson('/backup/auto', body: {'enabled': enabled});
}
