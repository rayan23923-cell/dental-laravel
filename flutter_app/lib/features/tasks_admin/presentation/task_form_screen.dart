import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/tasks_admin_repository.dart';
import '../domain/task_admin.dart';
import '../domain/task_scoring.dart';
import 'requirements_table.dart';
import 'scoring_editor.dart';
import 'tasks_admin_providers.dart';
import '../../../core/widgets/numeric_input.dart';
import '../../../core/widgets/tg_spinner.dart';

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

  // Requirements table (2026-10-17, as on the web): a case-sheet type with
  // a table pre-fills it when adding; every enabled row is its own task.
  List<ScoringTemplateRow>? _rows;
  final _passPercentController = TextEditingController();
  // Editing: the task's own points setup (web Tasks/Edit.vue). Off only
  // hides the points and totals; the lists are kept.
  TaskScoringSetup _scoring = TaskScoringSetup(measure: 'points');
  bool _usePoints = false;
  int? _loadedDepartmentId;

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
    _requiredCountController.dispose();
    _notesController.dispose();
    _gradeController.dispose();
    _passPercentController.dispose();
    super.dispose();
  }

  void _seed(TaskAdmin task) {
    if (_seeded) return;
    _seeded = true;
    _titleController.text = task.title;
    _requiredCountController.text = (task.requiredCount ?? 1).toString();
    _notesController.text = task.notes ?? '';
    _gradeController.text = task.grade?.toString() ?? '';
    _departmentId = task.departmentId;
    _stageId = task.stageId;
    _caseSheetTypeId = task.caseSheetTypeId;
    _isRequired = task.isRequired;
    _loadedDepartmentId = task.departmentId;
    if (task.scoring != null) _scoring = task.scoring!;
    _usePoints = task.scoring != null && !task.scoring!.pointsOff;
    _scoring.pointsOff = !_usePoints;
    _passPercentController.text = fmtPoints(task.departmentPassPercent);
  }

  /// The chosen stage's number (4 or 5) from its name, as the web reads it.
  int? _stageNumber(List<LookupItem> stages) {
    final name = stages.where((s) => s.id == _stageId).firstOrNull?.name ?? '';
    if (RegExp(r'fourth|رابع|\b4\b', caseSensitive: false).hasMatch(name)) return 4;
    if (RegExp(r'fifth|خامس|\b5\b', caseSensitive: false).hasMatch(name)) return 5;
    return null;
  }

  /// Rows of one stage only follow the chosen stage: the other stage's
  /// rows start switched off, and so do rows the template marks `off`.
  void _applyStage() {
    final rows = _rows;
    if (rows == null) return;
    final n = _stageNumber(ref.read(taskStagesProvider).valueOrNull ?? const []);
    for (final row in rows) {
      row.enabled = row.stage != null ? !row.off && (n == null || row.stage == n) : row.baseEnabled;
    }
  }

  void _pickCaseSheetType(int? id) {
    final template = id == null ? null : ref.read(taskScoringTemplatesProvider).valueOrNull?[id];
    _caseSheetTypeId = id;
    _rows = template?.freshRows();
    _passPercentController.text = fmtPoints(template?.passPercent);
    _applyStage();
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
    final t = ref.read(translationsProvider);
    if (_departmentId == null || _stageId == null || _caseSheetTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['tasksAdmin.selectDepartmentStageCaseSheetMsg']!)));
      return;
    }
    setState(() => _submitting = true);

    final passText = _passPercentController.text.trim();
    final passPercent = passText.isEmpty ? null : double.tryParse(passText);
    final rows = _isCreate ? _rows : null;
    final payload = <String, dynamic>{
      'title': _titleController.text.trim(),
      'department_id': _departmentId,
      'stage_id': _stageId,
      'case_sheet_type_id': _caseSheetTypeId,
      'required_count': int.tryParse(_requiredCountController.text.trim()) ?? 1,
      'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      'grade': _gradeController.text.trim().isEmpty ? null : double.tryParse(_gradeController.text.trim()),
      'is_required': _isRequired,
    };
    if (rows != null) {
      payload
        ..remove('title')
        ..remove('required_count')
        ..['rows'] = [for (final r in rows) r.toJson()]
        ..['pass_percent'] = passPercent;
    } else if (!_isCreate) {
      _scoring.pointsOff = !_usePoints;
      payload['scoring'] = _usePoints || _scoring.hasLists ? _scoring.toJson() : null;
      // Only sent for the department this task was loaded with.
      if (_departmentId == _loadedDepartmentId) payload['pass_percent'] = passPercent;
    }

    try {
      final repo = ref.read(tasksAdminRepositoryProvider);
      if (_isCreate) {
        try {
          await repo.create(payload);
        } on ValidationException catch (e) {
          // Already in this department (same check as the web form): ask,
          // then resend with allow_duplicates.
          if (!e.duplicate) rethrow;
          if (!mounted || !await _confirmDuplicate(e.message)) return;
          await repo.create({...payload, 'allow_duplicates': true});
        }
      } else {
        await repo.update(widget.taskId!, payload);
        ref.invalidate(taskAdminProvider(widget.taskId!));
      }
      ref.invalidate(taskAdminListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isCreate ? t['tasksAdmin.addedSuccess']! : t['tasksAdmin.savedSuccess']!)));
        Navigator.of(context).pop(_listFilter());
      }
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['tasksAdmin.saveFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Back on the list, filtered on this task's stage and department
  /// (same as the web, 2026-10-16), so the change shows straight away.
  Map<String, int?> _listFilter() =>
      {'educationTypeId': _educationTypeId, 'stageId': _stageId, 'departmentId': _departmentId};

  Future<bool> _confirmDuplicate(String message) async {
    final t = ref.read(translationsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t['tasksAdmin.duplicateTitle']!),
        content: Text('$message\n\n${t['tasksAdmin.duplicateConfirmBody']!}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t['tasksAdmin.cancel']!)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t['tasksAdmin.addAnyway']!)),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _delete() async {
    final t = ref.read(translationsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t['tasksAdmin.deleteTitle']!),
        content: Text(t['tasksAdmin.deleteConfirmBody']!),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t['tasksAdmin.cancel']!)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t['tasksAdmin.delete']!)),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(tasksAdminRepositoryProvider).delete(widget.taskId!);
      ref.invalidate(taskAdminListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['tasksAdmin.deletedSuccess']!)));
        Navigator.of(context).pop(_listFilter());
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['tasksAdmin.deleteFailed']!;
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
    final t = ref.watch(translationsProvider);
    // Loaded up front so picking a case-sheet type can pre-fill its table.
    final templatesAsync = _isCreate ? ref.watch(taskScoringTemplatesProvider) : null;

    if (taskAsync != null) {
      switch (taskAsync) {
        case AsyncError(:final error):
          return Scaffold(
            appBar: AppBar(title: Text(t['tasksAdmin.singularTitle']!)),
            body: Center(child: Text(error is ApiException ? error.userMessage : t['tasksAdmin.loadFailed']!)),
          );
        case AsyncData(:final value):
          _seed(value);
        default:
          return const Scaffold(body: Center(child: TgSpinner()));
      }
    }
    final stageItems = stagesAsync.valueOrNull;
    if (stageItems != null) _deriveEducationType(stageItems);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCreate ? t['tasksAdmin.newTitle']! : t['tasksAdmin.editTitle']!),
        actions: [
          if (!_isCreate) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_rows == null) ...[
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(labelText: t['tasksAdmin.titleLabel'], border: const OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? t['tasksAdmin.requiredField'] : null,
              ),
              const SizedBox(height: 16),
            ],
            educationTypesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => Text(t['tasksAdmin.loadEducationTypesFailed']!),
              data: (items) => DropdownButtonFormField<int>(
                initialValue: items.any((et) => et.id == _educationTypeId) ? _educationTypeId : null,
                decoration: InputDecoration(labelText: t['tasksAdmin.educationTypeLabel'], border: const OutlineInputBorder()),
                items: [for (final et in items) DropdownMenuItem(value: et.id, child: Text(et.name))],
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
              error: (_, __) => Text(t['tasksAdmin.loadStagesFailed']!),
              data: (items) {
                final filtered =
                    _educationTypeId == null ? items : items.where((s) => s.educationTypeId == _educationTypeId).toList();
                return DropdownButtonFormField<int>(
                  key: ValueKey('stage-$_educationTypeId'),
                  initialValue: filtered.any((s) => s.id == _stageId) ? _stageId : null,
                  decoration: InputDecoration(labelText: t['tasksAdmin.stageLabel'], border: const OutlineInputBorder()),
                  items: [for (final s in filtered) DropdownMenuItem(value: s.id, child: Text(s.name))],
                  onChanged: _educationTypeId == null
                      ? null
                      : (v) => setState(() {
                            if (v != _stageId) _departmentId = null;
                            _stageId = v;
                            _applyStage();
                          }),
                );
              },
            ),
            const SizedBox(height: 16),
            // Only the chosen stage's departments (2026-10-13, by request),
            // so the stage is picked first.
            departmentsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => Text(t['tasksAdmin.loadDepartmentsFailed']!),
              data: (items) {
                final filtered = items.where((d) => _stageId != null && d.stageId == _stageId).toList();
                return DropdownButtonFormField<int>(
                  key: ValueKey('department-$_stageId'),
                  initialValue: filtered.any((d) => d.id == _departmentId) ? _departmentId : null,
                  decoration: InputDecoration(labelText: t['tasksAdmin.departmentLabel'], border: const OutlineInputBorder()),
                  items: [for (final d in filtered) DropdownMenuItem(value: d.id, child: Text(d.name))],
                  onChanged: _stageId == null ? null : (v) => setState(() => _departmentId = v),
                );
              },
            ),
            const SizedBox(height: 16),
            caseSheetTypesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => Text(t['tasksAdmin.loadCaseSheetTypesFailed']!),
              data: (items) => DropdownButtonFormField<int>(
                initialValue: items.any((c) => c.id == _caseSheetTypeId) ? _caseSheetTypeId : null,
                decoration: InputDecoration(labelText: t['tasksAdmin.caseSheetTypeLabel'], border: const OutlineInputBorder()),
                items: [for (final c in items) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => setState(() {
                  if (_isCreate) {
                    _pickCaseSheetType(v);
                  } else {
                    _caseSheetTypeId = v;
                  }
                }),
              ),
            ),
            if (templatesAsync is AsyncError) ...[
              const SizedBox(height: 8),
              Text(t['taskScoring.loadTemplatesFailed']!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_rows != null) ...[
              const SizedBox(height: 16),
              RequirementsTable(
                key: ValueKey(_rows),
                rows: _rows!,
                caseSheetTypes: caseSheetTypesAsync.valueOrNull ?? const [],
                passPercentController: _passPercentController,
                t: t,
              ),
            ],
            const SizedBox(height: 16),
            Text(t['tasksAdmin.taskTypeLabel']!, style: Theme.of(context).textTheme.titleSmall),
            RadioGroup<bool>(
              groupValue: _isRequired,
              onChanged: (v) {
                if (v != null) setState(() => _isRequired = v);
              },
              child: Row(
                children: [
                  Expanded(child: RadioListTile<bool>(title: Text(t['tasksAdmin.required']!), value: true)),
                  Expanded(child: RadioListTile<bool>(title: Text(t['tasksAdmin.optional']!), value: false)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // One cap per doctor (2026-10-13, by request), as on the web.
            if (_rows == null) ...[
              TextFormField(
                controller: _requiredCountController,
                keyboardType: TextInputType.number,
                inputFormatters: digitsOnly,
                decoration: InputDecoration(labelText: t['tasksAdmin.requiredCountLabel'], border: const OutlineInputBorder()),
                validator: (v) => (int.tryParse(v?.trim() ?? '') ?? 0) < 1 ? t['tasksAdmin.requiredField'] : null,
              ),
              const SizedBox(height: 16),
            ],
            if (!_isCreate) ...[
              ScoringSection(
                scoring: _scoring,
                usePoints: _usePoints,
                onUsePoints: (on) => setState(() {
                  _usePoints = on;
                  _scoring.pointsOff = !on;
                }),
                passPercentController: _passPercentController,
                t: t,
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _gradeController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalOnly,
              decoration: InputDecoration(labelText: t['tasksAdmin.gradeLabel'], border: const OutlineInputBorder()),
              // Grade and notes are required (2026-10-13, by request), as on the web.
              validator: (v) {
                final grade = double.tryParse(v?.trim() ?? '');
                if (grade == null) return t['tasksAdmin.requiredField'];
                return grade < 0 || grade > 100 ? '0 - 100' : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(labelText: t['tasksAdmin.notesLabel'], border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? t['tasksAdmin.requiredField'] : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: TgSpinner(strokeWidth: 2))
                  : Text(t['tasksAdmin.save']!),
            ),
          ],
        ),
      ),
    );
  }
}
