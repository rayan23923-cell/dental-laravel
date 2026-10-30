import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/chat_list_tile.dart';
import '../data/department_roles_repository.dart';
import '../../../core/widgets/tg_spinner.dart';

final departmentRolesProvider = FutureProvider.autoDispose<DepartmentRolesPage>((ref) {
  return ref.watch(departmentRolesRepositoryProvider).fetch();
});

/// "أدوار الأقسام" (2026-10-17) — the web's `DepartmentRoles/Index`,
/// reached from the permissions screen as there: a staff member is made
/// senior (كبير القسم) or HR of one department of one stage; an
/// assignment can be switched off and on, or removed.
class DepartmentRolesScreen extends ConsumerWidget {
  const DepartmentRolesScreen({super.key});

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(departmentRolesProvider);
    } catch (e) {
      if (context.mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.userMessage : t['departmentRolesAdmin.failed']!)),
        );
      }
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, DepartmentRoleAssignment a) async {
    final t = ref.read(translationsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t['departmentRolesAdmin.removeConfirm']!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t['nav.cancel']!)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t['departmentRolesAdmin.remove']!, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _run(context, ref, () => ref.read(departmentRolesRepositoryProvider).remove(a.id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final pageAsync = ref.watch(departmentRolesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['departmentRolesAdmin.title']!)),
      floatingActionButton: pageAsync.hasValue
          ? FloatingActionButton.extended(
              onPressed: () async {
                final added = await showModalBottomSheet<bool>(
                  context: context,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => _AssignSheet(page: pageAsync.value!),
                );
                if (added == true) ref.invalidate(departmentRolesProvider);
              },
              icon: const Icon(Icons.add),
              label: Text(t['departmentRolesAdmin.assignRoleHeading']!),
            )
          : null,
      body: pageAsync.when(
        loading: () => const Center(child: TgSpinner()),
        error: (error, _) => Center(child: Text(error is ApiException ? error.userMessage : t['departmentRolesAdmin.failed']!)),
        data: (page) {
          if (page.assignments.isEmpty) {
            return Center(child: Text(t['departmentRolesAdmin.emptyList']!));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(departmentRolesProvider),
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 8, bottom: 88),
              itemCount: page.assignments.length,
              separatorBuilder: (_, __) => chatDivider,
              itemBuilder: (context, i) {
                final a = page.assignments[i];
                return ChatListTile(
                  title: a.userName,
                  color: a.active ? chatToneFor(a.id) : Colors.grey,
                  icon: a.roleType == 'hr' ? Icons.badge_outlined : Icons.workspace_premium_outlined,
                  subtitle: a.notes,
                  chips: [
                    ChatChip(
                      label: a.roleType == 'hr' ? t['departmentRolesAdmin.hrOption']! : t['departmentRolesAdmin.seniorOption']!,
                      icon: Icons.shield_outlined,
                      color: Colors.indigo,
                    ),
                    if (a.stageName != null) ChatChip(label: a.stageName!, icon: Icons.layers_outlined),
                    if (a.departmentName != null) ChatChip(label: a.departmentName!, icon: Icons.apartment_outlined, color: Colors.teal),
                    ChatChip(
                      label: a.active ? t['departmentRolesAdmin.active']! : t['departmentRolesAdmin.inactive']!,
                      icon: a.active ? Icons.check_circle : Icons.pause_circle_outline,
                      color: a.active ? Colors.green : Colors.grey,
                    ),
                  ],
                  actions: [
                    IconButton(
                      tooltip: a.active ? t['departmentRolesAdmin.deactivate']! : t['departmentRolesAdmin.reactivate']!,
                      icon: Icon(a.active ? Icons.toggle_on : Icons.toggle_off_outlined, color: a.active ? Colors.green : null),
                      onPressed: () => _run(context, ref, () => ref.read(departmentRolesRepositoryProvider).toggle(a.id)),
                    ),
                    IconButton(
                      tooltip: t['departmentRolesAdmin.remove']!,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _remove(context, ref, a),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _AssignSheet extends ConsumerStatefulWidget {
  const _AssignSheet({required this.page});
  final DepartmentRolesPage page;

  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  final _notes = TextEditingController();
  int? _userId;
  int? _stageId;
  int? _departmentId;
  String _roleType = 'senior';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = ref.read(translationsProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(departmentRolesRepositoryProvider).assign(
            userId: _userId!,
            stageId: _stageId!,
            departmentId: _departmentId!,
            roleType: _roleType,
            notes: _notes.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.userMessage : t['departmentRolesAdmin.failed']!);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final page = widget.page;
    // Each department belongs to one stage: only the chosen stage's are listed.
    final departments = [for (final d in page.departments) if (d.stageId == _stageId) d];
    final ready = _userId != null && _stageId != null && _departmentId != null && !_saving;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t['departmentRolesAdmin.assignRoleHeading']!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _userId,
                isExpanded: true,
                decoration: InputDecoration(labelText: t['departmentRolesAdmin.userPlaceholder'], border: const OutlineInputBorder()),
                items: [for (final u in page.users) DropdownMenuItem(value: u.id, child: Text(u.name, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _userId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _stageId,
                isExpanded: true,
                decoration: InputDecoration(labelText: t['departmentRolesAdmin.stageLabel'], border: const OutlineInputBorder()),
                items: [for (final s in page.stages) DropdownMenuItem(value: s.id, child: Text(s.name))],
                onChanged: (v) => setState(() {
                  _stageId = v;
                  _departmentId = null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                // Keyed by stage so the field resets when the stage changes.
                key: ValueKey(_stageId),
                initialValue: _departmentId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t['departmentRolesAdmin.departmentLabel'],
                  helperText: _stageId == null ? t['departmentRolesAdmin.selectStageFirst'] : null,
                  border: const OutlineInputBorder(),
                ),
                items: [for (final d in departments) DropdownMenuItem(value: d.id, child: Text(d.name))],
                onChanged: _stageId == null ? null : (v) => setState(() => _departmentId = v),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'senior', label: Text(t['departmentRolesAdmin.seniorOption']!)),
                  ButtonSegment(value: 'hr', label: Text(t['departmentRolesAdmin.hrOption']!)),
                ],
                selected: {_roleType},
                onSelectionChanged: (v) => setState(() => _roleType = v.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: InputDecoration(labelText: t['departmentRolesAdmin.notesLabel'], border: const OutlineInputBorder()),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: ready ? _save : null,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: TgSpinner(strokeWidth: 2))
                    : Text(t['departmentRolesAdmin.assignButton']!),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
