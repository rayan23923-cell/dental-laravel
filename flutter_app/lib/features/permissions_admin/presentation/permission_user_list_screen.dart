import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../domain/permission_admin.dart';
import 'permissions_admin_providers.dart';

class PermissionUserListScreen extends ConsumerWidget {
  const PermissionUserListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(permissionUserListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الصلاحيات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/users/new'),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('مستخدم جديد'),
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : 'تعذر التحميل.'),
        ),
        data: (users) {
          if (users.isEmpty) {
            return const Center(child: Text('لا يوجد مستخدمون.'));
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
