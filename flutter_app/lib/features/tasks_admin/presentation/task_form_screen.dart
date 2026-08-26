import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/network/api_exception.dart';
import '../data/tasks_admin_repository.dart';
import '../domain/task_admin.dart';
import 'tasks_admin_providers.dart';

class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({super.key, this.taskId, this.initialEducationTypeId, this.initialStageId});
  final int? taskId;

  // Carried over from the list screen's current filter (see
  // `task_list_screen.dart`'s FAB) when adding a task while one is active
  // there — null when it wasn't, in which case these fields start empty
  // and are picked manually, same as before this existed. Ignored when
  // editing an existing task (its own stage_id/derived education type wins).
  final int? initialEducationTypeId;
  final int? initialStageId;

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _requiredPerDoctorController = TextEditingController(text: '1');
  final _requiredCountController = TextEditingController(text: '1');
  final _notesController = TextEditingController();
  final _gradeController = TextEditingController();
  int? _departmentId;
  int? _stageId;
  int? _caseSheetTypeId;
  int? _educationTypeId;
  // Most tasks are mandatory today (there being no other option before this
  // field existed), so new tasks default to أساسية.
  bool _isRequired = true;
  bool _seeded = false;
  bool _educationTypeDerived = false;
  bool _submitting = false;

  bool get _isCreate => widget.taskId == null;

  @override
  void initState() {
    super.initState();
    if (_isCreate) {
      _stageId = widget.initialStageId;
      _educationTypeId = widget.initialEducationTypeId;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _requiredPerDoctorController.dispose();
    _requiredCountController.dispose();
    _notesController.dispose();
    _gradeController.dispose();
    super.dispose();
  }

  void _seed(TaskAdmin task) {
    if (_seeded) return;
    _seeded = true;
    _titleController.text = task.title;
    _requiredPerDoctorController.text = (task.requiredPerDoctor ?? 1).toString();
    _requiredCountController.text = (task.requiredCount ?? 1).toString();
    _notesController.text = task.notes ?? '';
    _gradeController.text = task.grade?.toString() ?? '';
    _departmentId = task.departmentId;
    _stageId = task.stageId;
    _caseSheetTypeId = task.caseSheetTypeId;
    _isRequired = task.isRequired;
  }

  // A task doesn't store its education type (same reason Tasks/Index.vue
  // and Tasks/Edit.vue derive it on the web side) — once stages have
  // loaded, find the one matching this task's stage and read its
  // education type, so the cascade below doesn't open looking reset.
  void _deriveEducationType(List<LookupItem> stages) {
    if (_educationTypeDerived || _isCreate) return;
    _educationTypeDerived = true;
    for (final s in stages) {
      if (s.id == _stageId) {
        _educationTypeId = s.educationTypeId;
        break;
      }
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    if (_departmentId == null || _stageId == null || _caseSheetTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار القسم والمرحلة ونوع النموذج.')));
      return;
    }
    setState(() => _submitting = true);

    final payload = {
      'title': _titleController.text.trim(),
      'department_id': _departmentId,
      'stage_id': _stageId,
      'case_sheet_type_id': _caseSheetTypeId,
      'required_per_doctor': int.tryParse(_requiredPerDoctorController.text.trim()) ?? 1,
      'required_count': int.tryParse(_requiredCountController.text.trim()) ?? 1,
      'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      'grade': _gradeController.text.trim().isEmpty ? null : double.tryParse(_gradeController.text.trim()),
      'is_required': _isRequired,
    };

    try {
      final repo = ref.read(tasksAdminRepositoryProvider);
      if (_isCreate) {
        await repo.create(payload);
      } else {
        await repo.update(widget.taskId!, payload);
        ref.invalidate(taskAdminProvider(widget.taskId!));
      }
      ref.invalidate(taskAdminListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isCreate ? 'تم إضافة المهمة.' : 'تم الحفظ.')));
        Navigator.of(context).pop();
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

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المهمة'),
        content: const Text('هل أنت متأكد من حذف هذه المهمة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(tasksAdminRepositoryProvider).delete(widget.taskId!);
      ref.invalidate(taskAdminListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحذف.')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحذف.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final departmentsAsync = ref.watch(taskDepartmentsProvider);
    final stagesAsync = ref.watch(taskStagesProvider);
    final educationTypesAsync = ref.watch(taskEducationTypesProvider);
    final caseSheetTypesAsync = ref.watch(taskCaseSheetTypesProvider);
    final taskAsync = _isCreate ? null : ref.watch(taskAdminProvider(widget.taskId!));

    if (taskAsync != null) {
      switch (taskAsync) {
        case AsyncError(:final error):
          return Scaffold(
            appBar: AppBar(title: const Text('مهمة')),
            body: Center(child: Text(error is ApiException ? error.userMessage : 'تعذر التحميل.')),
          );
        case AsyncData(:final value):
          _seed(value);
        default:
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
    }
    final stageItems = stagesAsync.valueOrNull;
    if (stageItems != null) _deriveEducationType(stageItems);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCreate ? 'مهمة جديدة' : 'تعديل المهمة'),
        actions: [
          if (!_isCreate) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'العنوان', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
            ),
            const SizedBox(height: 16),
            departmentsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('تعذر تحميل الأقسام.'),
              data: (items) => DropdownButtonFormField<int>(
                initialValue: items.any((d) => d.id == _departmentId) ? _departmentId : null,
                decoration: const InputDecoration(labelText: 'القسم', border: OutlineInputBorder()),
                items: [for (final d in items) DropdownMenuItem(value: d.id, child: Text(d.name))],
                onChanged: (v) => setState(() => _departmentId = v),
              ),
            ),
            const SizedBox(height: 16),
            educationTypesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('تعذر تحميل أنواع الدراسة.'),
              data: (items) => DropdownButtonFormField<int>(
                initialValue: items.any((t) => t.id == _educationTypeId) ? _educationTypeId : null,
                decoration: const InputDecoration(labelText: 'نوع الدراسة', border: OutlineInputBorder()),
                items: [for (final t in items) DropdownMenuItem(value: t.id, child: Text(t.name))],
                onChanged: (v) => setState(() {
                  _educationTypeId = v;
                  _stageId = null;
                }),
              ),
            ),
            const SizedBox(height: 16),
            // Education type -> stage cascade (UI-only, mirrors
            // task_list_screen.dart's own cascade exactly — `Task` has no
            // education_type_id column, so this never reaches the API, it
            // only narrows which stages are selectable here). Keyed on the
            // parent's value so the field is fully recreated (and its
            // `initialValue` re-evaluated) whenever education type changes.
            stagesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('تعذر تحميل المراحل.'),
              data: (items) {
                final filtered =
                    _educationTypeId == null ? items : items.where((s) => s.educationTypeId == _educationTypeId).toList();
                return DropdownButtonFormField<int>(
                  key: ValueKey('stage-$_educationTypeId'),
                  initialValue: filtered.any((s) => s.id == _stageId) ? _stageId : null,
                  decoration: const InputDecoration(labelText: 'المرحلة', border: OutlineInputBorder()),
                  items: [for (final s in filtered) DropdownMenuItem(value: s.id, child: Text(s.name))],
                  onChanged: _educationTypeId == null ? null : (v) => setState(() => _stageId = v),
                );
              },
            ),
            const SizedBox(height: 16),
            caseSheetTypesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('تعذر تحميل أنواع النماذج.'),
              data: (items) => DropdownButtonFormField<int>(
                initialValue: items.any((c) => c.id == _caseSheetTypeId) ? _caseSheetTypeId : null,
                decoration: const InputDecoration(labelText: 'نوع النموذج', border: OutlineInputBorder()),
                items: [for (final c in items) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => setState(() => _caseSheetTypeId = v),
              ),
            ),
            const SizedBox(height: 16),
            Text('نوع المهمة', style: Theme.of(context).textTheme.titleSmall),
            RadioGroup<bool>(
              groupValue: _isRequired,
              onChanged: (v) {
                if (v != null) setState(() => _isRequired = v);
              },
              child: const Row(
                children: [
                  Expanded(child: RadioListTile<bool>(title: Text('أساسية'), value: true)),
                  Expanded(child: RadioListTile<bool>(title: Text('اختيارية'), value: false)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _requiredPerDoctorController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'المطلوب لكل طبيب', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _requiredCountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'العدد المطلوب', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _gradeController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'الدرجة', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'ملاحظات', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
