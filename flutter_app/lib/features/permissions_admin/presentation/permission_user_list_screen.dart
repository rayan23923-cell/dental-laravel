import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../users_admin/domain/user_admin.dart';
import '../domain/permission_admin.dart';
import 'permissions_admin_providers.dart';

class PermissionUserListScreen extends ConsumerStatefulWidget {
  const PermissionUserListScreen({super.key});

  @override
  ConsumerState<PermissionUserListScreen> createState() => _PermissionUserListScreenState();
}

class _PermissionUserListScreenState extends ConsumerState<PermissionUserListScreen> {
  // Role filter (2026-10-14, by request), like the web page's chips.
  String? _role;

  @override
  Widget build(BuildContext context) {
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
          final counts = <String, int>{};
          for (final u in users) {
            counts[u.role] = (counts[u.role] ?? 0) + 1;
          }
          final shown = _role == null ? users : users.where((u) => u.role == _role).toList();
          return Column(
            children: [
              if (counts.length > 1)
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: ChoiceChip(
                          label: Text('${t['permissionsAdmin.allRoles']!} ${users.length}'),
                          selected: _role == null,
                          onSelected: (_) => setState(() => _role = null),
                        ),
                      ),
                      for (final e in counts.entries)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: ChoiceChip(
                            avatar: Icon(_roleStyle(e.key).$1, size: 16, color: _roleStyle(e.key).$2),
                            label: Text('${_roleLabel(e.key)} ${e.value}'),
                            selected: _role == e.key,
                            onSelected: (on) => setState(() => _role = on ? e.key : null),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(permissionUserListProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                    itemBuilder: (context, i) => _UserTile(user: shown[i]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

const _roleStyles = <String, (IconData, Color)>{
  'admin': (Icons.admin_panel_settings_outlined, Colors.indigo),
  'editor': (Icons.edit_note, Colors.lightBlue),
  'doctor': (Icons.medical_services_outlined, Colors.green),
  'accountant': (Icons.payments_outlined, Colors.orange),
  'senior': (Icons.workspace_premium_outlined, Colors.purple),
  'hr': (Icons.badge_outlined, Colors.pink),
  'reception': (Icons.confirmation_number_outlined, Colors.teal),
  'lab': (Icons.biotech_outlined, Colors.deepPurple),
};

(IconData, Color) _roleStyle(String role) => _roleStyles[role] ?? (Icons.person_outline, Colors.blueGrey);

String _roleLabel(String role) =>
    kAssignableUserRoles.firstWhere((r) => r.$1 == role, orElse: () => (role, role)).$2;

/// Chat-list row (2026-10-13, by request: "مشابه لتصميم انستاكرام او
/// تيليجرام"), matching the web page: avatar, name and a coloured role chip.
class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});
  final PermissionUser user;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _roleStyle(user.role);
    final roleLabel = _roleLabel(user.role);
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
