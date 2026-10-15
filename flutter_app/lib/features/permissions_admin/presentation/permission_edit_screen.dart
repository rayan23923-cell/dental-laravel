import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/settings_list.dart';
import '../data/permissions_admin_repository.dart';
import '../domain/permission_admin.dart';
import 'permissions_admin_providers.dart';
import 'permissions_editor.dart';

/// One account's permissions as a settings list (2026-10-14, by request),
/// the app's copy of the web `Permissions/Edit` page: an account card,
/// then the shared [PermissionsEditor], and a save bar at the bottom.
class PermissionEditScreen extends ConsumerStatefulWidget {
  const PermissionEditScreen({super.key, required this.userId});
  final int userId;

  @override
  ConsumerState<PermissionEditScreen> createState() => _PermissionEditScreenState();
}

class _PermissionEditScreenState extends ConsumerState<PermissionEditScreen> {
  Set<String> _grants = {};
  PermissionScopeSelection _scope = PermissionScopeSelection();
  bool _seeded = false;
  bool _submitting = false;
  bool _dirty = false;

  void _seed(PermissionsDetail detail) {
    if (_seeded) return;
    _seeded = true;
    _grants = Set.of(detail.granted);
    _scope = PermissionScopeSelection.fromScope(detail.scope);
  }

  Future<void> _save() async {
    setState(() => _submitting = true);
    try {
      await ref.read(permissionsAdminRepositoryProvider).update(widget.userId, _grants.toList(), _scope);
      ref.invalidate(permissionsDetailProvider(widget.userId));
      if (mounted) {
        setState(() => _dirty = false);
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['permissionsAdmin.savedSuccess']!)));
      }
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['permissionsAdmin.saveFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(permissionsDetailProvider(widget.userId));
    final usersAsync = ref.watch(permissionUserListProvider);
    final t = ref.watch(translationsProvider);
    PermissionUser? user;
    for (final u in usersAsync.valueOrNull ?? const <PermissionUser>[]) {
      if (u.id == widget.userId) {
        user = u;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(t['permissionsAdmin.title']!)),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : t['permissionsAdmin.loadFailed']!),
        ),
        data: (detail) {
          _seed(detail);
          final allPairs = [
            for (final m in detail.modules)
              for (final p in m.permissions) '${m.key}.${p.key}',
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _AccountCard(user: user, granted: _grants.length, total: allPairs.length, grantedLabel: t['permissionsAdmin.grantedShort']!),
              const SizedBox(height: 20),
              PermissionsEditor(
                modules: detail.modules,
                scopeOptions: detail.scopeOptions,
                grants: _grants,
                scope: _scope,
                onChanged: () => setState(() => _dirty = true),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _dirty ? t['permissionsAdmin.unsavedChanges']! : t['permissionsAdmin.allSaved']!,
                  style: TextStyle(fontSize: 12, color: _dirty ? Colors.orange.shade800 : Colors.grey),
                ),
              ),
              FilledButton.icon(
                onPressed: (_submitting || !_dirty) ? null : _save,
                icon: _submitting
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(t['permissionsAdmin.save']!),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user, required this.granted, required this.total, required this.grantedLabel});
  final PermissionUser? user;
  final int granted;
  final int total;
  final String grantedLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = user?.fullName ?? '';
    return SettingsGroupCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primaryContainer,
                child: Text(name.trim().isEmpty ? '?' : name.trim()[0], style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (user != null) Text(user!.username, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Column(
                children: [
                  // Forced LTR so "granted/total" isn't reordered in Arabic.
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '$granted/$total',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.primary),
                    ),
                  ),
                  Text(grantedLabel, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
