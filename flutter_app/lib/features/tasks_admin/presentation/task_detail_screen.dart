import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/chat_list_tile.dart';
import '../../../core/widgets/qr_dialog.dart';
import '../../task_instances/domain/task_instance_status.dart';
import '../../task_instances/presentation/status_badge.dart';
import '../data/tasks_admin_repository.dart';
import '../domain/task_admin.dart';
import '../domain/task_instance_admin.dart';
import 'tasks_admin_providers.dart';
import '../../../core/theme/muted_colors.dart';

/// Port of the web `Tasks/Show.vue` (2026-10-17): the task's details and
/// its instances — each with its QR, an
/// edit (status, grade, notes), "mark complete" and remove. Opened from
/// the tasks list; editing the task itself is the app bar's pencil.
class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final int taskId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  bool _busy = false;

  TasksAdminRepository get _repo => ref.read(tasksAdminRepositoryProvider);

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs one change, then reloads the instances.
  Future<void> _run(Future<void> Function() action, String successKey) async {
    final t = ref.read(translationsProvider);
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(taskWithInstancesProvider(widget.taskId));
      _snack(t[successKey]!);
    } catch (e) {
      _snack(e is ApiException ? e.userMessage : t['tasksAdmin.saveFailed']!);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(TaskInstanceAdmin instance) async {
    final t = ref.read(translationsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t['taskDetailAdmin.removeTitle']!),
        content: Text(t['taskDetailAdmin.removeConfirm']!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t['tasksAdmin.cancel']!)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t['taskDetailAdmin.remove']!)),
        ],
      ),
    );
    if (ok == true) await _run(() => _repo.deleteInstance(instance.id), 'taskDetailAdmin.removed');
  }

  Future<void> _edit(TaskInstanceAdmin instance) async {
    final result = await showDialog<({TaskInstanceStatus status, double? grade, String? notes})>(
      context: context,
      builder: (context) => _InstanceEditDialog(instance: instance),
    );
    if (result == null) return;
    await _run(
      () => _repo.updateInstance(instance.id, status: result.status.toJson(), grade: result.grade, notes: result.notes),
      'taskDetailAdmin.saved',
    );
  }

  Future<void> _complete(TaskInstanceAdmin instance) => _run(
        () => _repo.updateInstance(instance.id, status: 'completed', grade: instance.grade, notes: instance.notes),
        'taskDetailAdmin.saved',
      );

  /// The form pops with the saved task's filter; hand it on to the list.
  Future<void> _editTask() async {
    final result = await context.push<Map<String, int?>>('/admin/tasks/${widget.taskId}');
    if (!mounted) return;
    if (result != null) {
      context.pop(result);
    } else {
      ref.invalidate(taskWithInstancesProvider(widget.taskId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final async = ref.watch(taskWithInstancesProvider(widget.taskId));

    return Scaffold(
      appBar: AppBar(
        title: Text(async.valueOrNull?.task.title ?? t['tasksAdmin.singularTitle']!),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: t['tasksAdmin.editTitle'], onPressed: _editTask),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e is ApiException ? e.userMessage : t['tasksAdmin.loadFailed']!)),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(taskWithInstancesProvider(widget.taskId)),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TaskInfoCard(task: data.task, t: t),
              const SizedBox(height: 16),
              // Cases start from task progress, with their patient and steps;
              // the direct "assign to a doctor" box is gone (2026-10-19, by request).
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
                child: Text(
                  '${t['taskDetailAdmin.instancesHeading']!} (${data.instances.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: data.instances.isEmpty
                    ? ListTile(title: Text(t['taskDetailAdmin.noInstances']!))
                    : Column(
                        children: [
                          for (var i = 0; i < data.instances.length; i++) ...[
                            if (i > 0) chatDivider,
                            _instanceTile(data.instances[i], t),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _instanceTile(TaskInstanceAdmin instance, Map<String, String> t) {
    final date = DateFormat('yyyy/MM/dd');
    return ChatListTile(
      title: instance.doctorName ?? '—',
      color: chatToneFor(instance.doctorId ?? instance.id),
      chips: [
        StatusBadge(status: instance.status),
        if (instance.assignedDate != null) ChatChip(label: date.format(instance.assignedDate!), icon: Icons.event_outlined),
        if (instance.grade != null)
          ChatChip(label: '${t['taskDetailAdmin.grade']!}: ${instance.grade!.toStringAsFixed(2)}', icon: Icons.grade_outlined, color: Colors.indigo),
      ],
      actions: [
        PopupMenuButton<String>(
          enabled: !_busy,
          onSelected: (action) => switch (action) {
            'qr' => showQrDialog(
                context,
                imagePath: '/task-instances/${instance.id}/qr',
                title: t['myTasks.qrCaseTitle']!,
                caption: instance.doctorName,
              ),
            'complete' => _complete(instance),
            'edit' => _edit(instance),
            _ => _remove(instance),
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'qr', child: ListTile(leading: const Icon(Icons.qr_code_2), title: Text(t['taskDetailAdmin.qr']!))),
            if (instance.status != TaskInstanceStatus.completed)
              PopupMenuItem(
                value: 'complete',
                child: ListTile(leading: const Icon(Icons.task_alt, color: Colors.green), title: Text(t['taskDetailAdmin.markComplete']!)),
              ),
            PopupMenuItem(value: 'edit', child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(t['taskDetailAdmin.edit']!))),
            PopupMenuItem(
              value: 'remove',
              child: ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: Text(t['taskDetailAdmin.remove']!)),
            ),
          ],
        ),
      ],
      onTap: _busy ? null : () => _edit(instance),
    );
  }
}

class _TaskInfoCard extends StatelessWidget {
  const _TaskInfoCard({required this.task, required this.t});
  final TaskAdmin task;
  final Map<String, String> t;

  @override
  Widget build(BuildContext context) {
    Widget item(String label, String value) => SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: context.mutedText)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                item(t['tasksAdmin.departmentLabel']!, task.departmentName ?? '—'),
                item(t['tasksAdmin.caseSheetTypeLabel']!, task.caseSheetTypeNameAr ?? '—'),
                item(t['tasksAdmin.stageLabel']!, task.stageName ?? '—'),
                item(t['tasksAdmin.requiredCountLabel']!, '${task.requiredCount ?? '—'}'),
              ],
            ),
            if (task.notes != null && task.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(task.notes!, style: TextStyle(color: context.mutedText)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Status, grade and notes of one instance, as `PUT /task-instances/{id}`
/// takes them.
class _InstanceEditDialog extends ConsumerStatefulWidget {
  const _InstanceEditDialog({required this.instance});
  final TaskInstanceAdmin instance;

  @override
  ConsumerState<_InstanceEditDialog> createState() => _InstanceEditDialogState();
}

class _InstanceEditDialogState extends ConsumerState<_InstanceEditDialog> {
  late TaskInstanceStatus _status = widget.instance.status;
  late final _grade = TextEditingController(text: widget.instance.grade?.toString() ?? '');
  late final _notes = TextEditingController(text: widget.instance.notes ?? '');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _grade.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    return AlertDialog(
      title: Text(widget.instance.doctorName ?? t['taskDetailAdmin.edit']!),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final s in TaskInstanceStatus.values)
                    ChoiceChip(label: Text(s.label(t)), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _grade,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: t['taskDetailAdmin.grade']),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final g = double.tryParse(v.trim());
                  return g == null || g < 0 || g > 999.99 ? t['taskDetailAdmin.gradeInvalid'] : null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: InputDecoration(labelText: t['tasksAdmin.notesLabel']),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t['tasksAdmin.cancel']!)),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, (
              status: _status,
              grade: double.tryParse(_grade.text.trim()),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ));
          },
          child: Text(t['tasksAdmin.save']!),
        ),
      ],
    );
  }
}
