import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/widgets/settings_list.dart';
import '../domain/permission_admin.dart';

/// The permissions editor (2026-10-14): "نطاق الوصول" and the module
/// permissions as collapsible settings rows with switches. Shared by the
/// permissions screen and the add-user form, so both show the same list —
/// the app's copy of the web `Components/Permissions/PermissionsEditor`.
///
/// It edits [grants] ("module.permission" pairs) and [scope] in place and
/// calls [onChanged] after each change. The access scope cascades:
/// education types first, then only the stages of the chosen types, then
/// only the departments of the chosen stages. On the top levels (types,
/// academic sessions) nothing picked means nothing, and "الكل" is its own
/// choice (2026-10-18, by request); stages and departments with nothing
/// picked follow the level above, the same rules the server keeps
/// (`App\Services\ScopeHelper`).
class PermissionsEditor extends ConsumerStatefulWidget {
  const PermissionsEditor({
    super.key,
    required this.modules,
    required this.scopeOptions,
    required this.grants,
    required this.scope,
    required this.onChanged,
  });

  final List<PermissionModule> modules;
  final PermissionScopeOptions scopeOptions;
  final Set<String> grants;
  final PermissionScopeSelection scope;
  final VoidCallback onChanged;

  @override
  ConsumerState<PermissionsEditor> createState() => _PermissionsEditorState();
}

class _PermissionsEditorState extends ConsumerState<PermissionsEditor> {
  String? _open;

  void _toggleOpen(String key) => setState(() => _open = _open == key ? null : key);

  void _setGrants(Iterable<String> pairs, bool on) {
    setState(() => on ? widget.grants.addAll(pairs) : widget.grants.removeAll(pairs));
    widget.onChanged();
  }

  // ── Cascade ──────────────────────────────────────────────────────────
  List<LookupItem> _visibleStages(PermissionScopeOptions o) {
    final types = widget.scope.educationTypeIds;
    return types.isEmpty ? o.stages : o.stages.where((s) => types.contains(s.educationTypeId)).toList();
  }

  List<LookupItem> _visibleDepartments(PermissionScopeOptions o) {
    final List<int>? stages = widget.scope.stageIds.isNotEmpty
        ? widget.scope.stageIds
        : widget.scope.educationTypeIds.isNotEmpty
        ? _visibleStages(o).map((s) => s.id).toList()
        : null;
    return stages == null ? o.departments : o.departments.where((d) => stages.contains(d.stageId)).toList();
  }

  /// Unticking a type or stage drops the stages and departments under it.
  void _prune(PermissionScopeOptions o) {
    final stageIds = _visibleStages(o).map((s) => s.id).toSet();
    widget.scope.stageIds.removeWhere((id) => !stageIds.contains(id));
    final deptIds = _visibleDepartments(o).map((d) => d.id).toSet();
    widget.scope.departmentIds.removeWhere((id) => !deptIds.contains(id));
  }

  void _setScope(PermissionScopeOptions o, String dimension, int id, bool on) {
    setState(() {
      final list = widget.scope.listFor(dimension);
      list.remove(id);
      if (on) {
        list.add(id);
        widget.scope.setAll(dimension, false);
      }
      _prune(o);
    });
    widget.onChanged();
  }

  /// "الكل" is on: nothing picked and, on a top level, the flag set.
  bool _allOn(String dimension) =>
      widget.scope.listFor(dimension).isEmpty && (widget.scope.allFor(dimension) ?? true);

  /// "الكل" toggles on a top level; on a lower level it clears the picks so
  /// the level follows the one above.
  void _clearScope(PermissionScopeOptions o, String dimension) {
    setState(() {
      final wasOn = _allOn(dimension);
      widget.scope.listFor(dimension).clear();
      widget.scope.setAll(dimension, !wasOn);
      _prune(o);
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final o = widget.scopeOptions;
    final allPairs = [
      for (final m in widget.modules)
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
          widget.scope.educationTypeIds.isNotEmpty ? t['permissionsAdmin.filteredByTypes']! : ''),
      _ScopeDim('departments', Icons.domain_outlined, Colors.lightBlue.shade600, t['permissionsAdmin.departmentsLabel']!,
          departments, o.departments, (d) => stageName(d.stageId),
          widget.scope.stageIds.isNotEmpty
              ? t['permissionsAdmin.filteredByStages']!
              : widget.scope.educationTypeIds.isNotEmpty
              ? t['permissionsAdmin.filteredByTypes']!
              : ''),
      _ScopeDim('academic_sessions', Icons.event_outlined, Colors.green.shade600,
          t['permissionsAdmin.academicSessionsLabel']!, o.academicSessions, o.academicSessions, null, ''),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            for (final module in widget.modules) _moduleSection(t, module),
          ],
        ),
      ],
    );
  }

  String _scopeSummary(Map<String, String> t, _ScopeDim dim) {
    final ids = widget.scope.listFor(dim.key);
    final top = widget.scope.allFor(dim.key) != null;
    final typesNone = widget.scope.educationTypeIds.isEmpty && !widget.scope.allEducationTypes;
    if (ids.isEmpty && (top ? !_allOn(dim.key) : typesNone && widget.scope.stageIds.isEmpty)) {
      return t['permissionsAdmin.scopeNone']!;
    }
    if (ids.isEmpty) {
      return dim.filteredBy.isEmpty ? t['permissionsAdmin.unrestricted']! : '${t['permissionsAdmin.unrestricted']!} ${dim.filteredBy}';
    }
    return dim.all
        .where((x) => ids.contains(x.id))
        .map((x) => x.stageName != null ? '${x.name} (${x.stageName})' : x.name)
        .join('، ');
  }

  List<Widget> _scopeFields(Map<String, String> t, PermissionScopeOptions o, _ScopeDim dim) {
    final selected = widget.scope.listFor(dim.key);
    final allOn = _allOn(dim.key);
    final top = widget.scope.allFor(dim.key) != null;
    final scheme = Theme.of(context).colorScheme;
    final groups = <String, List<LookupItem>>{};
    for (final item in dim.options) {
      groups.putIfAbsent(dim.groupOf?.call(item) ?? '', () => []).add(item);
    }
    return [
      Material(
        color: allOn ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: allOn ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant),
        ),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.all_inclusive),
          title: Text(t['permissionsAdmin.scopeAll']!, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: allOn ? Icon(Icons.check_circle, color: scheme.primary) : null,
          onTap: () => _clearScope(o, dim.key),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(
          top
              ? t['permissionsAdmin.scopeHintTop']!
              : dim.filteredBy.isEmpty
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
    final granted = module.permissions.where((p) => widget.grants.contains('${module.key}.${p.key}')).toList();
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
            value: widget.grants.contains('${module.key}.${p.key}'),
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
  'stages': (Icons.stairs_outlined, Colors.deepPurple),
  'education_types': (Icons.school_outlined, Colors.amber),
  'departments': (Icons.domain_outlined, Colors.lightBlue),
  'case_sheet_types': (Icons.description_outlined, Colors.blueGrey),
  'task_progress': (Icons.trending_up, Colors.green),
  'patient_screening': (Icons.fact_check_outlined, Colors.pinkAccent),
  'reports': (Icons.bar_chart, Colors.purple),
  'settings': (Icons.settings_outlined, Colors.grey),
  'printer_settings': (Icons.print_outlined, Colors.green),
  'payments': (Icons.payments_outlined, Colors.orange),
  'register_settings': (Icons.tune, Colors.brown),
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
