import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../form_settings/presentation/grade_picker.dart';
import '../../tasks_admin/domain/task_scoring.dart';

/// A case's steps, signed one after another with each one's grade
/// (2026-10-18, by request), the app's port of the web's
/// `TaskStepsList.vue`. [data] is the case's `/case-sheets/instances/{id}/work`
/// response (`steps`, `can_sign`); signing returns the same shape, handed
/// to [onUpdated]. Only the next step can be signed, only the last undone.
class TaskStepsList extends ConsumerStatefulWidget {
  const TaskStepsList({super.key, required this.taskInstanceId, required this.data, required this.onUpdated});

  final int taskInstanceId;
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onUpdated;

  @override
  ConsumerState<TaskStepsList> createState() => _TaskStepsListState();
}

class _TaskStepsListState extends ConsumerState<TaskStepsList> {
  final _grade = TextEditingController();
  // A step added to this case alone, with its name and top grade (2026-10-19, by request).
  final _extraLabel = TextEditingController();
  final _extraMax = TextEditingController(text: '10');
  bool _adding = false;
  bool _busy = false;
  String? _error;

  String get _path => '/case-sheets/instances/${widget.taskInstanceId}/steps';

  List<Map<String, dynamic>> get _steps =>
      ((widget.data['steps'] as List<dynamic>?) ?? const []).whereType<Map<String, dynamic>>().toList();

  @override
  void dispose() {
    _grade.dispose();
    _extraLabel.dispose();
    _extraMax.dispose();
    super.dispose();
  }

  Future<void> _run(Future<dynamic> Function(ApiClient client) call) async {
    final t = ref.read(translationsProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await call(ref.read(apiClientProvider)) as Map<String, dynamic>;
      _grade.clear();
      widget.onUpdated(d);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = switch (e) {
          ValidationException(:final errors) when errors.isNotEmpty => errors.values.first.first,
          ApiException() => e.userMessage,
          _ => t['taskSteps.failed'],
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sign(Map<String, dynamic> step) {
    final t = ref.read(translationsProvider);
    final max = (step['max'] as num?)?.toDouble();
    double? grade;
    // Grades switched off for the whole system (2026-10-22): signed without one.
    if (max != null && widget.data['grades_on'] != false) {
      grade = double.tryParse(_grade.text.trim().replaceAll(',', '.'));
      if (grade == null || grade < 0 || grade > max) {
        setState(() => _error = trf(t['taskSteps.gradeRange']!, {'max': fmtPoints(max)}));
        return;
      }
    }
    _run((client) => client.postJson(_path, body: {'step': step['key'], 'grade': grade}));
  }

  void _addExtra() {
    final t = ref.read(translationsProvider);
    final label = _extraLabel.text.trim();
    final max = double.tryParse(_extraMax.text.trim().replaceAll(',', '.'));
    if (label.isEmpty || max == null || max <= 0 || max > 100) {
      setState(() => _error = t['taskSteps.addStepName']);
      return;
    }
    _run((client) => client.postJson(
          '/case-sheets/instances/${widget.taskInstanceId}/extra-steps',
          body: {'label': label, 'max': max},
        )).then((_) {
      if (mounted && _error == null) {
        _extraLabel.clear();
        _extraMax.text = '10';
        setState(() => _adding = false);
      }
    });
  }

  void _removeExtra(Map<String, dynamic> step) => _run(
        (client) => client.deleteJsonData(
          '/case-sheets/instances/${widget.taskInstanceId}/extra-steps',
          body: {'step': step['key']},
        ),
      );

  void _undo(Map<String, dynamic> step) => _run((client) => client.deleteJsonData(_path, body: {'step': step['key']}));

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final steps = _steps;
    final canSign = widget.data['can_sign'] == true;
    if (steps.isEmpty && !canSign) return const SizedBox.shrink();
    final next = steps.indexWhere((s) => s['signed'] != true);
    final last = steps.lastIndexWhere((s) => s['signed'] == true);
    final done = steps.where((s) => s['signed'] == true).length;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (steps.isNotEmpty)
        Row(
          children: [
            Expanded(
              child: Text(t['taskSteps.title']!, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(
              trf(t['taskSteps.progress']!, {'done': done, 'total': steps.length}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < steps.length; i++)
          _row(t, colors, steps[i], i, isNext: i == next, isLast: i == last, canSign: canSign),
        // Adding a step: its own permission and system switch (2026-10-22).
        if ((widget.data['can_add_step'] as bool?) ?? canSign) _addForm(t),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: TextStyle(color: colors.error)),
          ),
      ],
    );
  }

  Widget _addForm(Map<String, String> t) {
    if (!_adding) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: _busy ? null : () => setState(() => _adding = true),
          icon: const Icon(Icons.add, size: 18),
          label: Text(t['taskSteps.addStep']!),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _extraLabel,
              maxLength: 100,
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                labelText: t['taskSteps.addStepName'],
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _extraMax,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                isDense: true,
                labelText: t['taskSteps.addStepMax'],
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            onPressed: _busy ? null : _addExtra,
            icon: const Icon(Icons.check),
            tooltip: t['taskSteps.addStepSave'],
          ),
          IconButton(
            onPressed: _busy ? null : () => setState(() => _adding = false),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _row(
    Map<String, String> t,
    ColorScheme colors,
    Map<String, dynamic> step,
    int i, {
    required bool isNext,
    required bool isLast,
    required bool canSign,
  }) {
    final signed = step['signed'] == true;
    final max = step['max'] as num?;
    final accent = signed ? Colors.green.shade700 : (isNext ? colors.primary : colors.outline);

    return Opacity(
      opacity: signed || isNext ? 1 : 0.6,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: signed
              ? Colors.green.withValues(alpha: 0.08)
              : (isNext ? colors.primary.withValues(alpha: 0.06) : null),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: accent,
                  child: signed
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text('${i + 1}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: step['label']?.toString() ?? '',
                      children: [
                        if (step['extra'] == true)
                          TextSpan(
                            text: '  ${t['taskSteps.extraBadge']}',
                            style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.normal),
                          ),
                      ],
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                if (signed && max != null) Text('${fmtPoints(step['grade'] as num?)} / ${fmtPoints(max)}'),
                if (signed && canSign && isLast)
                  TextButton(
                    onPressed: _busy ? null : () => _undo(step),
                    child: Text(t['taskSteps.undo']!, style: TextStyle(color: colors.error)),
                  ),
                if (!signed && !isNext && max != null)
                  Text('/ ${fmtPoints(max)}', style: Theme.of(context).textTheme.bodySmall),
                if (step['extra'] == true && !signed && canSign)
                  IconButton(
                    onPressed: _busy ? null : () => _removeExtra(step),
                    icon: Icon(Icons.delete_outline, size: 20, color: colors.error),
                    tooltip: t['taskSteps.removeStep'],
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            // No signing a graded step without its grade (2026-10-22, by request).
            if (!signed && isNext && canSign && max != null && widget.data['grades_on'] == false)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(t['taskSteps.gradesOff']!, style: TextStyle(color: Colors.amber.shade800, fontSize: 12)),
              )
            else if (!signed && isNext && canSign)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    if (max != null && widget.data['grades_on'] != false) ...[
                      // Picked with a tap (2026-10-22, by request).
                      OutlinedButton.icon(
                        // The theme's full-width minimum (Size.fromHeight)
                        // can't lay out inside a Row: the button vanished.
                        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
                        icon: const Icon(Icons.touch_app_outlined, size: 18),
                        label: Text('${_grade.text.isEmpty ? '—' : _grade.text} / ${fmtPoints(max)}'),
                        onPressed: () async {
                          final picked = await showGradePickerSheet(
                            context,
                            max: max.toDouble(),
                            initial: double.tryParse(_grade.text),
                            title: '${t['gradePicker.title']!} · ${step['label']}',
                            confirm: t['gradePicker.confirm']!,
                            labels: {
                              'outOf': t['gradePicker.outOf']!,
                              'full': t['gradePicker.full']!,
                              'half': t['gradePicker.half']!,
                              'clear': t['gradePicker.clear']!,
                            },
                          );
                          if (picked != null) setState(() => _grade.text = fmtPoints(picked));
                        },
                      ),
                      const Spacer(),
                    ] else
                      const Spacer(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                      onPressed: _busy ? null : () => _sign(step),
                      icon: const Icon(Icons.draw_outlined, size: 18),
                      label: Text(t['taskSteps.sign']!),
                    ),
                  ],
                ),
              ),
            if (signed && step['signed_by'] != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 32, top: 2),
                child: Text(
                  '${trf(t['taskSteps.signedBy']!, {'name': step['signed_by']})}${step['signed_at'] != null ? ' — ${step['signed_at']}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The steps in a bottom sheet, for task progress: right after a case
/// starts and from a started case's "الخطوات" button.
Future<void> showTaskStepsSheet(BuildContext context, {required int taskInstanceId, required String title}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _TaskStepsSheet(taskInstanceId: taskInstanceId, title: title),
  );
}

class _TaskStepsSheet extends ConsumerStatefulWidget {
  const _TaskStepsSheet({required this.taskInstanceId, required this.title});
  final int taskInstanceId;
  final String title;

  @override
  ConsumerState<_TaskStepsSheet> createState() => _TaskStepsSheetState();
}

class _TaskStepsSheetState extends ConsumerState<_TaskStepsSheet> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref
        .read(apiClientProvider)
        .getJson('/case-sheets/instances/${widget.taskInstanceId}/work')
        .then((d) => mounted ? setState(() => _data = d as Map<String, dynamic>) : null)
        .catchError(
          (Object e) => mounted ? setState(() => _error = e is ApiException ? e.userMessage : e.toString()) : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final data = _data;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t['taskSteps.modalTitle']!, style: Theme.of(context).textTheme.titleMedium),
              Text(widget.title, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
              else if (data == null)
                const Center(
                  child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
                )
              else ...[
                TaskStepsList(
                  taskInstanceId: widget.taskInstanceId,
                  data: data,
                  onUpdated: (d) => setState(() => _data = {...data, ...d}),
                ),
                if (data['points'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      trf(t['taskScoring.pointsValue']!, {'n': fmtPoints(data['points'] as num?)}),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
