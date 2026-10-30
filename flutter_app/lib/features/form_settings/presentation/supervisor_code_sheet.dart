import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/form_settings_repository.dart';
import 'grade_picker.dart';
import '../../../core/widgets/tg_spinner.dart';

/// The supervisor's code typed on the student's own account (2026-10-22,
/// by request): starts the task ([instanceId] null), or signs the case's
/// next step with its grade, adds a step (2026-10-30), or completes it. Returns the supervisor's
/// name once done. See `SupervisorCodeController` on the server.
Future<String?> showSupervisorCodeSheet(
  BuildContext context, {
  required DoctorFormSettings settings,
  required int taskId,
  required String taskTitle,
  required int slot,
  int? instanceId,
  double? taskGrade,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _SupervisorCodeSheet(
      settings: settings,
      taskId: taskId,
      taskTitle: taskTitle,
      slot: slot,
      instanceId: instanceId,
      taskGrade: taskGrade,
    ),
  );
}

class _SupervisorCodeSheet extends ConsumerStatefulWidget {
  const _SupervisorCodeSheet({
    required this.settings,
    required this.taskId,
    required this.taskTitle,
    required this.slot,
    this.instanceId,
    this.taskGrade,
  });

  final DoctorFormSettings settings;
  final int taskId;
  final String taskTitle;
  final int slot;
  final int? instanceId;
  final double? taskGrade;

  @override
  ConsumerState<_SupervisorCodeSheet> createState() => _SupervisorCodeSheetState();
}

class _SupervisorCodeSheetState extends ConsumerState<_SupervisorCodeSheet> {
  late String _action;
  late String _formType;
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  final _notes = TextEditingController();
  // A step added to the case: its name and top grade.
  final _stepLabel = TextEditingController();
  final _stepMax = TextEditingController();
  double? _grade;
  XFile? _photo;
  Uint8List? _preview;
  List<CaseStep>? _steps;
  bool _busy = false;
  String? _error;

  List<String> get _actions => widget.instanceId == null
      ? [if (widget.settings.codeActions.contains('start')) 'start']
      : [for (final a in const ['step', 'add_step', 'finish']) if (widget.settings.codeActions.contains(a)) a];

  CaseStep? get _nextStep => _steps?.where((s) => !s.signed).firstOrNull;

  bool get _gradesOn => widget.settings.on('grade_entry_enabled');

  double? get _gradeMax => !_gradesOn ? null : switch (_action) {
        'step' => _nextStep?.max,
        'finish' => widget.taskGrade,
        _ => null,
      };

  @override
  void initState() {
    super.initState();
    _action = _actions.firstOrNull ?? 'start';
    _formType = widget.settings.electronic ? 'electronic' : 'paper';
    if (widget.instanceId != null) _loadSteps();
  }

  Future<void> _loadSteps() async {
    try {
      final steps = await ref.read(formSettingsRepositoryProvider).steps(widget.instanceId!);
      if (!mounted) return;
      setState(() {
        _steps = steps;
        if (_action == 'step' && _nextStep == null && _actions.contains('finish')) _action = 'finish';
      });
    } catch (_) {
      if (mounted) setState(() => _steps = const []);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _codeFocus.dispose();
    _notes.dispose();
    _stepLabel.dispose();
    _stepMax.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _photo = file;
      _preview = bytes;
    });
  }

  bool get _ready =>
      !_busy &&
      _code.text.length == 6 &&
      (_action != 'step' || (_nextStep != null && (_nextStep!.max == null || !_gradesOn || _grade != null))) &&
      (_action != 'add_step' || (_stepLabel.text.trim().isNotEmpty && (double.tryParse(_stepMax.text.trim()) ?? 0) > 0));

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(formSettingsRepositoryProvider);
    try {
      final name = switch (_action) {
        'start' => await repo.start(
            taskId: widget.taskId,
            code: _code.text,
            formType: _formType,
            photo: _formType == 'paper' ? _photo : null,
            notes: _notes.text,
          ),
        'step' => await repo.signStep(widget.instanceId!, code: _code.text, step: _nextStep!.key, grade: _grade),
        'add_step' => await repo.addStep(widget.instanceId!, code: _code.text, label: _stepLabel.text.trim(), max: double.parse(_stepMax.text.trim())),
        _ => await repo.complete(widget.instanceId!, code: _code.text, grade: _grade, notes: _notes.text),
      };
      if (mounted) Navigator.of(context).pop(name);
    } catch (e) {
      final t = ref.read(translationsProvider);
      setState(() {
        _code.clear();
        _error = e is ValidationException
            ? (e.errors.values.expand((v) => v).firstOrNull ?? e.message)
            : e is ApiException
                ? e.userMessage
                : t['supervisorCode.failed']!;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final scheme = Theme.of(context).colorScheme;
    final gradeMax = _gradeMax;

    Widget choice(String value, String selectedValue, IconData icon, String label, VoidCallback onTap) {
      final selected = value == selectedValue;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected ? scheme.primaryContainer : null,
              border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: 2),
            ),
            child: Column(
              children: [
                Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(height: 4),
                Text(label, textAlign: TextAlign.center, style: TextStyle(color: selected ? scheme.primary : scheme.onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }

    final titleKey = switch (_action) {
      'start' => 'supervisorCode.startTitle',
      'step' => 'supervisorCode.stepTitle',
      'add_step' => 'supervisorCode.addStepTitle',
      _ => 'supervisorCode.finishTitle',
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.pin_outlined, color: Colors.deepPurple.shade700),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t[titleKey]!, style: Theme.of(context).textTheme.titleMedium),
                      Text('${widget.taskTitle} · #${widget.slot}', style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_actions.length > 1) ...[
              Row(
                children: [
                  for (final a in _actions) ...[
                    if (a != _actions.first) const SizedBox(width: 8),
                    choice(
                      a,
                      _action,
                      switch (a) { 'step' => Icons.checklist, 'add_step' => Icons.playlist_add, _ => Icons.task_alt },
                      t[switch (a) { 'step' => 'supervisorCode.actionStep', 'add_step' => 'supervisorCode.actionAddStep', _ => 'supervisorCode.actionFinish' }]!,
                      () => setState(() {
                        _action = a;
                        _grade = null;
                      }),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (_action == 'start') ...[
              if (widget.settings.electronic && widget.settings.paper) ...[
                Row(
                  children: [
                    choice('electronic', _formType, Icons.description_outlined, t['taskRequests.electronicForm']!, () => setState(() => _formType = 'electronic')),
                    const SizedBox(width: 8),
                    choice('paper', _formType, Icons.photo_camera_outlined, t['taskRequests.paperForm']!, () => setState(() => _formType = 'paper')),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (_formType == 'paper') ...[
                Text(t['supervisorCode.photoOptional']!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                if (_preview != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_preview!, height: 160, fit: BoxFit.cover)),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera), label: Text(t['taskRequests.camera']!))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(onPressed: () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: Text(t['taskRequests.gallery']!))),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ],
            if (_action == 'step') ...[
              if (_steps == null)
                Padding(padding: const EdgeInsets.all(12), child: Center(child: Text(t['supervisorCode.loadingSteps']!)))
              else if (_nextStep == null)
                Card(color: Colors.green.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Text(t['supervisorCode.allStepsSigned']!)))
              else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t['supervisorCode.nextStep']!.replaceAll('{label}', _nextStep!.label),
                          style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer),
                        ),
                      ),
                      Text('${_steps!.where((s) => s.signed).length}/${_steps!.length}', style: TextStyle(color: scheme.onPrimaryContainer)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
            if (_action == 'add_step') ...[
              TextField(
                controller: _stepLabel,
                maxLength: 100,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: t['supervisorCode.stepName'], border: const OutlineInputBorder(), counterText: ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stepMax,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: t['supervisorCode.stepMax'], border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
            ],
            if (_action == 'finish' && gradeMax != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(t['supervisorCode.finalGrade']!, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            if (gradeMax != null && (_action == 'finish' || _nextStep != null)) ...[
              GradePicker(
                key: ValueKey('$_action-${_nextStep?.key}'),
                max: gradeMax,
                value: _grade,
                onChanged: (v) => setState(() => _grade = v),
                labels: {
                  'outOf': t['gradePicker.outOf']!,
                  'full': t['gradePicker.full']!,
                  'half': t['gradePicker.half']!,
                  'clear': t['gradePicker.clear']!,
                },
              ),
              const SizedBox(height: 12),
            ],
            if (_action == 'start' || _action == 'finish') ...[
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: InputDecoration(labelText: t['supervisorCode.notes'], border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
            ],
            // The code itself: six boxes over one hidden field.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(18)),
              child: Column(
                children: [
                  Text(t['supervisorCode.codeLabel']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _codeFocus.requestFocus(),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < 6; i++)
                                Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  width: 40,
                                  height: 50,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: scheme.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _code.text.length == i ? scheme.primary : scheme.outlineVariant, width: 2),
                                  ),
                                  child: Text(i < _code.text.length ? '•' : '', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                        ),
                        Opacity(
                          opacity: 0,
                          child: TextField(
                            controller: _code,
                            focusNode: _codeFocus,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _ready ? _submit() : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(t['supervisorCode.codeHint']!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _ready ? _submit : null,
              icon: _busy ? const SizedBox(width: 18, height: 18, child: TgSpinner(strokeWidth: 2)) : const Icon(Icons.verified),
              label: Text(t['supervisorCode.confirm']!),
            ),
          ],
        ),
      ),
    );
  }
}
