import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/muted_colors.dart';
import '../data/users_admin_repository.dart';
import '../domain/user_admin.dart';
import '../../../core/widgets/tg_spinner.dart';

final managedUsersProvider = FutureProvider.autoDispose<List<ManagedUser>>((ref) {
  return ref.watch(usersAdminRepositoryProvider).list();
});

/// Users management (2026-10-21, by request), the web's `Users/Index`:
/// every account with its role and whether it's switched off; a row opens
/// the account's details and password.
class UserListScreen extends ConsumerStatefulWidget {
  const UserListScreen({super.key});

  @override
  ConsumerState<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends ConsumerState<UserListScreen> {
  String _query = '';
  // Role filter, like the web page's chips (2026-10-22, by request).
  String? _role;

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(managedUsersProvider);
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t['usersAdmin.indexTitle']!),
        actions: [
          IconButton(
            tooltip: t['settingsMenu.permissions'],
            icon: const Icon(Icons.lock_outline),
            onPressed: () => context.push('/admin/permissions'),
          ),
          IconButton(
            tooltip: t['departmentRolesAdmin.shortTitle'],
            icon: const Icon(Icons.workspace_premium_outlined),
            onPressed: () => context.push('/admin/department-roles'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await context.push('/admin/users/new');
          ref.invalidate(managedUsersProvider);
        },
        tooltip: t['permissionsAdmin.newUserFab'],
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: usersAsync.when(
        loading: () => const Center(child: TgSpinner()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : t['usersAdmin.loadFailed']!),
        ),
        data: (users) {
          final q = _query.trim().toLowerCase();
          final counts = <String, int>{};
          for (final u in users) {
            counts[u.role] = (counts[u.role] ?? 0) + 1;
          }
          final shown = users
              .where((u) =>
                  (_role == null || u.role == _role) &&
                  (q.isEmpty ||
                      [u.fullName, u.username, u.email, u.phone ?? '', userRoleLabel(u.role)]
                          .any((v) => v.toLowerCase().contains(q))))
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: t['usersAdmin.searchHint'],
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
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
                            label: Text('${userRoleLabel(e.key)} ${e.value}'),
                            selected: _role == e.key,
                            onSelected: (on) => setState(() => _role = on ? e.key : null),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(managedUsersProvider),
                  child: shown.isEmpty
                      ? ListView(children: [
                          Padding(
                            padding: const EdgeInsets.all(48),
                            child: Center(child: Text(t['usersAdmin.empty']!)),
                          ),
                        ])
                      : ListView.separated(
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

class _UserTile extends ConsumerWidget {
  const _UserTile({required this.user});
  final ManagedUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final name = user.fullName.trim().isEmpty ? user.username : user.fullName;
    final color = user.active ? Theme.of(context).colorScheme.primary : Colors.grey;

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
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(userRoleLabel(user.role), style: TextStyle(fontSize: 12, color: context.mutedText)),
            if (!user.active)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(t['usersAdmin.inactive']!,
                    style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500)),
              ),
            Text('@${user.username}', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: context.faintText)),
          ],
        ),
      ),
      trailing: Icon(Icons.chevron_left, color: context.faintText),
      onTap: () async {
        await context.push('/admin/users/${user.id}');
        ref.invalidate(managedUsersProvider);
      },
    );
  }
}
