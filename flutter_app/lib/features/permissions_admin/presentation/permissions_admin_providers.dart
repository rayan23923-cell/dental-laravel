import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/permissions_admin_repository.dart';
import '../domain/permission_admin.dart';

final permissionUserListProvider = FutureProvider.autoDispose<List<PermissionUser>>((ref) {
  return ref.watch(permissionsAdminRepositoryProvider).listUsers();
});

final permissionsDetailProvider = FutureProvider.autoDispose.family<PermissionsDetail, int>((ref, userId) {
  return ref.watch(permissionsAdminRepositoryProvider).fetch(userId);
});
