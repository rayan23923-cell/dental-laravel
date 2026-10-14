import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/settings_list.dart';
import '../data/permissions_admin_repository.dart';
import '../domain/permission_admin.dart';
import 'permissions_admin_providers.dart';

/// One account's permissions as a settings list (2026-10-14, by request),
/// the app's copy of the web `Permissions/Edit` page: an account card,
/// then "نطاق الوصول" and the module permissions as collapsible rows with
/// a coloured icon and a summary, switches, and a save bar at the bottom.
///
/// The access scope cascades: education types first, then only the stages
/// of the chosen types, then only the departments of the chosen stages.
/// Nothing picked on a level means everything within the level above,
/// the same rule the server keeps (`App\Services\ScopeHelper`).
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
  String? _open;

  void _seed(PermissionsDetail detail) {
    if (_seeded) return;
    _seeded = true;
    _grants = Set.of(detail.granted);
    _scope = PermissionScopeSelection.fromScope(detail.scope);
  }

  void _toggleOpen(String key) => setState(() => _open = _open == key ? null : key);

  void _setGrants(Iterable<String> pairs, bool on) {
    setState(() {
      on ? _grants.addAll(pairs) : _grants.removeAll(pairs);
      _dirty = true;
    });
  }

  // ── Cascade ──────────────────────────────────────────────────────────
  List<LookupItem> _visibleStages(PermissionScopeOptions o) {
    final types = _scope.educationTypeIds;
    return types.isEmpty ? o.stages : o.stages.where((s) => types.contains(s.educationTypeId)).toList();
  }

  List<LookupItem> _visibleDepartments(PermissionScopeOptions o) {
    final List<int>? stages = _scope.stageIds.isNotEmpty
        ? _scope.stageIds
        : _scope.educationTypeIds.isNotEmpty
        ? _visibleStages(o).map((s) => s.id).toList()
        : null;
    return stages == null ? o.departments : o.departments.where((d) => stages.contains(d.stageId)).toList();
  }

  /// Unticking a type or stage drops the stages and departments under it.
  void _prune(PermissionScopeOptions o) {
    final stageIds = _visibleStages(o).map((s) => s.id).toSet();
    _scope.stageIds.removeWhere((id) => !stageIds.contains(id));
    final deptIds = _visibleDepartments(o).map((d) => d.id).toSet();
    _scope.departmentIds.removeWhere((id) => !deptIds.contains(id));
  }

  void _setScope(PermissionScopeOptions o, String dimension, int id, bool on) {
    setState(() {
      final list = _scope.listFor(dimension);
      list.remove(id);
      if (on) list.add(id);
      _prune(o);
      _dirty = true;
    });
  }

  void _clearScope(PermissionScopeOptions o, String dimension) {
    setState(() {
      _scope.listFor(dimension).clear();
      _prune(o);
      _dirty = true;
    });
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
          final o = detail.scopeOptions;
          final allPairs = [
            for (final m in detail.modules)
              for (final p in m.permissions) '${m.key}.${p.key}',
          ];
          final stages = _visibleStages(o);
          final departments = _visibleDepartments(o);
          String typeName(int? id) =>
              o.educationTypes.where((e) => e.id == id).map((e) => e.name).firstOrNull ?? t['permissionsAdmin.noType']!;
          String stageName(int? id) {
            final s = o.stages.where((e) => e.id == id).firstOrNull;
            if (s == null) return t['permissionsAdmin.noStage']!;
            return '${s.name} · ${typeName(s.educationTypeId)}';
          }

          final scopeRows = [
            _ScopeDim('education_types', Icons.school_outlined, Colors.amber.shade600, t['permissionsAdmin.educationTypesLabel']!,
                o.educationTypes, o.educationTypes, null, ''),
            _ScopeDim('stages', Icons.stairs_outlined, Colors.deepPurple.shade400, t['permissionsAdmin.stagesLabel']!, stages,
                o.stages, (s) => typeName(s.educationTypeId),
                _scope.educationTypeIds.isNotEmpty ? t['permissionsAdmin.filteredByTypes']! : ''),
            _ScopeDim('departments', Icons.domain_outlined, Colors.lightBlue.shade600, t['permissionsAdmin.departmentsLabel']!,
                departments, o.departments, (d) => stageName(d.stageId),
                _scope.stageIds.isNotEmpty
                    ? t['permissionsAdmin.filteredByStages']!
                    : _scope.educationTypeIds.isNotEmpty
                    ? t['permissionsAdmin.filteredByTypes']!
                    : ''),
            _ScopeDim('academic_sessions', Icons.event_outlined, Colors.green.shade600,
                t['permissionsAdmin.academicSessionsLabel']!, o.academicSessions, o.academicSessions, null, ''),
          ];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _AccountCard(user: user, granted: _grants.length, total: allPairs.length, grantedLabel: t['permissionsAdmin.grantedShort']!),
              const SizedBox(height: 20),
              SettingsGroupHeader(t['permissionsAdmin.scopeTitle']!),
              SettingsGroupCard(
                children: [
                  for (final dim in scopeRows)
                    SettingsSection(
                      icon: dim.icon,
                      color: dim.color,
                      title: dim.label,
                      summary: _scopeSummary(t, dim),
                      open: _open == 'scope-${dim.key}',
                      onToggle: () => _toggleOpen('scope-${dim.key}'),
                      children: _scopeFields(t, o, dim),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: SettingsGroupHeader(t['permissionsAdmin.groupPermissions']!)),
                  TextButton(onPressed: () => _setGrants(allPairs, true), child: Text(t['permissionsAdmin.selectAll']!)),
                  TextButton(onPressed: () => _setGrants(allPairs, false), child: Text(t['permissionsAdmin.clearAll']!)),
                ],
              ),
              SettingsGroupCard(
                children: [
                  for (final module in detail.modules) _moduleSection(t, module),
                ],
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

  String _scopeSummary(Map<String, String> t, _ScopeDim dim) {
    final ids = _scope.listFor(dim.key);
    if (ids.isEmpty) {
      return dim.filteredBy.isEmpty ? t['permissionsAdmin.unrestricted']! : '${t['permissionsAdmin.unrestricted']!} ${dim.filteredBy}';
    }
    return dim.all
        .where((x) => ids.contains(x.id))
        .map((x) => x.stageName != null ? '${x.name} (${x.stageName})' : x.name)
        .join('، ');
  }

  List<Widget> _scopeFields(Map<String, String> t, PermissionScopeOptions o, _ScopeDim dim) {
    final selected = _scope.listFor(dim.key);
    final scheme = Theme.of(context).colorScheme;
    final groups = <String, List<LookupItem>>{};
    for (final item in dim.options) {
      groups.putIfAbsent(dim.groupOf?.call(item) ?? '', () => []).add(item);
    }
    return [
      Material(
        color: selected.isEmpty ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected.isEmpty ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant),
        ),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.all_inclusive),
          title: Text(t['permissionsAdmin.scopeAll']!, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: selected.isEmpty ? Icon(Icons.check_circle, color: scheme.primary) : null,
          onTap: () => _clearScope(o, dim.key),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(
          dim.filteredBy.isEmpty
              ? t['permissionsAdmin.scopeHint']!
              : trf(t['permissionsAdmin.scopeHintFiltered']!, {'level': dim.filteredBy}),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ),
      if (dim.options.isEmpty)
        Text(t['permissionsAdmin.noOptionsAvailable']!, style: const TextStyle(color: Colors.grey)),
      for (final entry in groups.entries) ...[
        if (groups.length > 1 && entry.key.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, top: 8, bottom: 4),
            child: Text(
              entry.key,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
            ),
          ),
        for (final item in entry.value)
          SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(item.name),
            value: selected.contains(item.id),
            onChanged: (v) => _setScope(o, dim.key, item.id, v),
          ),
      ],
    ];
  }

  Widget _moduleSection(Map<String, String> t, PermissionModule module) {
    final pairs = [for (final p in module.permissions) '${module.key}.${p.key}'];
    final granted = module.permissions.where((p) => _grants.contains('${module.key}.${p.key}')).toList();
    final summary = granted.isEmpty
        ? t['permissionsAdmin.noAccess']!
        : granted.length == module.permissions.length
        ? t['permissionsAdmin.fullAccess']!
        : granted.map((p) => p.label).join('، ');
    final style = _moduleStyles[module.key] ?? (Icons.shield_outlined, Colors.blueGrey);
    return SettingsSection(
      icon: style.$1,
      color: style.$2,
      title: module.name,
      summary: summary,
      open: _open == 'module-${module.key}',
      onToggle: () => _toggleOpen('module-${module.key}'),
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(t['permissionsAdmin.allActions']!, style: const TextStyle(fontWeight: FontWeight.w600)),
          value: granted.length == module.permissions.length,
          onChanged: (v) => _setGrants(pairs, v),
        ),
        for (final p in module.permissions)
          SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(p.label),
            value: _grants.contains('${module.key}.${p.key}'),
            onChanged: (v) => _setGrants(['${module.key}.${p.key}'], v),
          ),
      ],
    );
  }
}

const _moduleStyles = <String, (IconData, Color)>{
  'dashboard': (Icons.dashboard_outlined, Colors.indigo),
  'users': (Icons.manage_accounts_outlined, Colors.blue),
  'doctors': (Icons.medical_services_outlined, Colors.teal),
  'patients': (Icons.personal_injury_outlined, Colors.pink),
  'tasks': (Icons.assignment_outlined, Colors.orange),
  'groups': (Icons.groups_outlined, Colors.cyan),
  'clinic_chairs': (Icons.chair_outlined, Colors.lightGreen),
  'stages': (Icons.stairs_outlined, Colors.deepPurple),
  'education_types': (Icons.school_outlined, Colors.amber),
  'departments': (Icons.domain_outlined, Colors.lightBlue),
  'task_progress': (Icons.trending_up, Colors.green),
  'patient_screening': (Icons.fact_check_outlined, Colors.pinkAccent),
  'reports': (Icons.bar_chart, Colors.purple),
  'settings': (Icons.settings_outlined, Colors.grey),
};

class _ScopeDim {
  const _ScopeDim(this.key, this.icon, this.color, this.label, this.options, this.all, this.groupOf, this.filteredBy);
  final String key;
  final IconData icon;
  final Color color;
  final String label;

  /// What can be picked now (within the level above).
  final List<LookupItem> options;

  /// Every option, for naming what is already picked.
  final List<LookupItem> all;
  final String Function(LookupItem)? groupOf;
  final String filteredBy;
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
