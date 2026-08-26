import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup_admin_repository.dart';
import '../domain/backup_status.dart';

final backupStatusProvider = FutureProvider.autoDispose<BackupStatus>((ref) {
  return ref.watch(backupAdminRepositoryProvider).fetch();
});
