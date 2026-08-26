import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/permissions_admin_repository.dart';
import '../domain/permission_admin.dart';
import 'permissions_admin_providers.dart';

/// One `ExpansionTile` per module with a checkbox per action — a vertical,
/// scrollable layout rather than the web app's 11×N grid, which doesn't
/// fit a phone screen. Each module's header also shows an N/total grant
/// count so the state is visible without expanding every tile.
class PermissionEditScreen extends ConsumerStatefulWidget {
  const PermissionEditScreen({super.key, required this.userId});
  final int userId;

  @override
  ConsumerState<PermissionEditScreen> createState() => _PermissionEditScreenState();
}

class _PermissionEditScreenState extends ConsumerState<PermissionEditScreen> {
  Set<String> _grants = {};
  bool _seeded = false;
  bool _submitting = false;
  bool _dirty = false;

  void _seed(PermissionsDetail detail) {
    if (_seeded) return;
    _seeded = true;
    _grants = Set.of(detail.granted);
  }

  void _toggle(String pair, bool value) {
    setState(() {
      if (value) {
        _grants.add(pair);
      } else {
        _grants.remove(pair);
      }
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _submitting = true);
    try {
      await ref.read(permissionsAdminRepositoryProvider).update(widget.userId, _grants.toList());
      ref.invalidate(permissionsDetailProvider(widget.userId));
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الصلاحيات.')));
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحفظ.';
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
    final cachedUsers = usersAsync.valueOrNull ?? const <PermissionUser>[];
    String? userName;
    for (final u in cachedUsers) {
      if (u.id == widget.userId) {
        userName = u.fullName;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(userName ?? 'الصلاحيات')),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(error is ApiException ? error.userMessage : 'تعذر التحميل.'),
        ),
        data: (detail) {
          _seed(detail);
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final module in detail.modules) _ModuleTile(module: module, grants: _grants, onToggle: _toggle),
              const SizedBox(height: 88),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_submitting || !_dirty) ? null : _save,
        icon: _submitting
            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.save_outlined),
        label: const Text('حفظ'),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module, required this.grants, required this.onToggle});
  final PermissionModule module;
  final Set<String> grants;
  final void Function(String pair, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    final grantedCount = module.permissions.where((p) => grants.contains('${module.key}.${p.key}')).length;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        title: Text(module.name),
        // Forced LTR: inside an RTL (Arabic) ancestor, the Unicode bidi
        // algorithm reorders a plain "$granted / $total" string so the
        // total renders first — silently swapping which number means
        // what. Confirmed live: "1 / 2" rendered as "2 / 1".
        subtitle: Directionality(
          textDirection: TextDirection.ltr,
          child: Text('$grantedCount / ${module.permissions.length}'),
        ),
        children: [
          for (final permission in module.permissions)
            CheckboxListTile(
              value: grants.contains('${module.key}.${permission.key}'),
              title: Text(permission.label),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => onToggle('${module.key}.${permission.key}', v ?? false),
            ),
        ],
      ),
    );
  }
}
