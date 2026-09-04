import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../domain/permission_admin.dart';
import 'permissions_admin_providers.dart';

class PermissionUserListScreen extends ConsumerWidget {
  const PermissionUserListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(permissionUserListProvider);
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['permissionsAdmin.title']!)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/users/new'),
        icon: const Icon(Icons.person_add_outlined),
        label: Text(t['permissionsAdmin.newUserFab']!),
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : t['permissionsAdmin.loadFailed']!),
        ),
        data: (users) {
          if (users.isEmpty) {
            return Center(child: Text(t['permissionsAdmin.emptyUsers']!));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(permissionUserListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _UserTile(user: users[i]),
            ),
          );
        },
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});
  final PermissionUser user;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(user.fullName),
        subtitle: Text('${user.username} · ${user.role}'),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => context.push('/admin/permissions/${user.id}'),
      ),
    );
  }
}
