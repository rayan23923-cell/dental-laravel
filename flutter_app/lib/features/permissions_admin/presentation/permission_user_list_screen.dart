import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../users_admin/domain/user_admin.dart';
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/admin/users/new'),
        tooltip: t['permissionsAdmin.newUserFab'],
        child: const Icon(Icons.person_add_alt_1),
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
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: users.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
              itemBuilder: (context, i) => _UserTile(user: users[i]),
            ),
          );
        },
      ),
    );
  }
}

/// Chat-list row (2026-10-13, by request: "مشابه لتصميم انستاكرام او
/// تيليجرام"), matching the web page: avatar, name and a coloured role chip.
class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});
  final PermissionUser user;

  static const _styles = <String, (IconData, Color)>{
    'admin': (Icons.admin_panel_settings_outlined, Colors.indigo),
    'editor': (Icons.edit_note, Colors.lightBlue),
    'doctor': (Icons.medical_services_outlined, Colors.green),
    'accountant': (Icons.payments_outlined, Colors.orange),
    'senior': (Icons.workspace_premium_outlined, Colors.purple),
    'hr': (Icons.badge_outlined, Colors.pink),
    'reception': (Icons.confirmation_number_outlined, Colors.teal),
    'lab': (Icons.biotech_outlined, Colors.deepPurple),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _styles[user.role] ?? (Icons.person_outline, Colors.blueGrey);
    final roleLabel = kAssignableUserRoles
        .firstWhere((r) => r.$1 == user.role, orElse: () => (user.role, user.role))
        .$2;
    final name = user.fullName.trim().isEmpty ? user.username : user.fullName;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: color,
        foregroundColor: Colors.white,
        child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(roleLabel, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
      trailing: const Icon(Icons.chevron_left, color: Colors.black26),
      onTap: () => context.push('/admin/permissions/${user.id}'),
    );
  }
}
