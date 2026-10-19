import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../tasks_admin/domain/task_scoring.dart';
import '../../tasks_admin/domain/work_items.dart';
import 'task_steps_list.dart';

/// The linked task's points on its case sheet (2026-10-17), the app's port
/// of the web's `TaskWorkPanel.vue` + `WorkItemsInput.vue`: the same work,
/// grades and checklist the task-progress dialogs record, read from and
/// saved to the task instance (`/case-sheets/instances/{id}/work`), so the
/// app, the web and task progress always show one set of points. A task
/// graded by the sheet's own steps (prosthodontics) shows what they add up
/// to, with only hand-added steps graded here. The server decides who may
/// edit (`can_edit`: staff with task_progress finish); a doctor reads only.
class TaskWorkPanel extends ConsumerStatefulWidget {
  const TaskWorkPanel({super.key, required this.taskInstanceId});

  final int taskInstanceId;

  @override
  ConsumerState<TaskWorkPanel> createState() => _TaskWorkPanelState();
}

class _TaskWorkPanelState extends ConsumerState<TaskWorkPanel> {
  Map<String, dynamic>? _data;
  TaskScoringSetup _scoring = TaskScoringSetup();
  List<WorkItemForm> _items = [];

  /// Grades of steps added by hand, keyed by step; the sheet's own steps are graded on the sheet.
  Map<String, double?> _stepGrades = {};
  bool _saving = false;
  String? _message;
  String? _error;

  String get _path => '/case-sheets/instances/${widget.taskInstanceId}/work';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(apiClientProvider).getJson(_path) as Map<String, dynamic>;
      _apply(d);
    } catch (_) {
      // No panel when the work can't be read (no access, offline), as on the web.
    }
  }

  void _apply(Map<String, dynamic> d) {
    if (!mounted) return;
    setState(() {
      _data = d;
      _scoring = TaskScoringSetup.maybe(d['scoring']) ?? TaskScoringSetup();
      _items = _fromSheet ? [] : workItemsToForm(_scoring, d['work_items'] as List<dynamic>?);
      _stepGrades = {
        for (final w in _workItems)
          if (w['custom'] == true) w['step'].toString(): (w['points'] as num?)?.toDouble(),
      };
    });
  }

  bool get _fromSheet => _data?['from_sheet'] == true;
  bool get _canEdit => _data?['can_edit'] == true;
  List<Map<String, dynamic>> get _workItems =>
      ((_data?['work_items'] as List<dynamic>?) ?? const []).whereType<Map<String, dynamic>>().toList();
  num? get _points => _data?['points'] as num?;

  Future<void> _save() async {
    final t = ref.read(translationsProvider);
    setState(() {
      _saving = true;
      _message = _error = null;
    });
    try {
      final payload = _fromSheet
          ? {'step_grades': _stepGrades}
          : {
              'work_items': [for (final i in _items) i.toJson()],
            };
      final d = await ref.read(apiClientProvider).putJson(_path, body: payload) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _data = {...?_data, 'work_items': d['work_items'], 'points': d['points']};
        _message = t['taskScoring.saved'];
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = switch (e) {
          ValidationException(:final errors) when errors.isNotEmpty => errors.values.first.first,
          ApiException() => e.userMessage,
          _ => t['taskScoring.saveFailed'],
        },
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final data = _data;
    // The sheet's own stages are signed and graded in its own section, so the
    // panel lists only the other steps (2026-10-19, by request).
    final panelSteps = ((data?['steps'] as List<dynamic>?) ?? const [])
        .where((s) => s is Map && s['on_sheet'] != true)
        .toList();
    final hasSteps = panelSteps.isNotEmpty;
    if (data == null || !(_fromSheet || _scoring.hasWork || hasSteps)) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final minPoints = _scoring.minPoints;
    final reached = _points != null && minPoints != null && _points! >= minPoints;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t['taskScoring.sheetPanel']!,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                      if (data['title'] != null)
                        Text(data['title'].toString(), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (_points != null)
                  Chip(
                    avatar: reached ? Icon(Icons.check_circle, size: 18, color: colors.onPrimary) : null,
                    backgroundColor: reached ? Colors.green.shade700 : colors.primary,
                    label: Text(
                      minPoints != null && !_scoring.pointsOff
                          ? '${trf(t['taskScoring.pointsValue']!, {'n': fmtPoints(_points)})} / ${fmtPoints(minPoints)}'
                          : trf(t['taskScoring.pointsValue']!, {'n': fmtPoints(_points)}),
                      style: TextStyle(color: colors.onPrimary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // The case's steps, signed one after another (2026-10-18, by request).
            // With the "add a step" button for supervisors when the task has steps (2026-10-19).
            if (hasSteps || (data['can_sign'] == true && ((data['steps'] as List<dynamic>?) ?? const []).isNotEmpty)) ...[
              TaskStepsList(
                taskInstanceId: widget.taskInstanceId,
                data: {...data, 'steps': panelSteps},
                onUpdated: _apply,
              ),
              const SizedBox(height: 8),
            ],
            // Each grade shows once (2026-10-19, by request): the sheet's stages in
            // its own section, the other steps in the list above.
            if (_fromSheet)
              ..._sheetSteps(t, colors, withRows: !hasSteps)
            else if (_scoring.hasWork && !(hasSteps && _scoring.options.isEmpty))
              _WorkItemsInput(
                scoring: _scoring,
                items: _items,
                enabled: _canEdit,
                t: t,
                onChanged: () => setState(() {}),
              ),
            if (!_fromSheet && _scoring.hasWork && !(hasSteps && _scoring.options.isEmpty) && !_canEdit)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(t['taskScoring.supervisorOnly']!, style: Theme.of(context).textTheme.bodySmall),
              ),
            if (_canEdit &&
                !(hasSteps && (_fromSheet || _scoring.options.isEmpty)) &&
                ((!_fromSheet && _scoring.hasWork) || _workItems.any((w) => w['custom'] == true)))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    FilledButton(onPressed: _saving ? null : _save, child: Text(t['taskScoring.savePoints']!)),
                    if (_message != null) Text(_message!, style: TextStyle(color: Colors.green.shade700)),
                    if (_error != null) Text(_error!, style: TextStyle(color: colors.error)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The total, with the hand-added steps' grades when [withRows]; the
  /// sheet's own stages are graded in its own section.
  List<Widget> _sheetSteps(Map<String, String> t, ColorScheme colors, {required bool withRows}) {
    final maxTotal = _workItems.fold<double>(0, (s, w) => s + ((w['max'] as num?)?.toDouble() ?? 0));
    return [
      Text(t['taskScoring.fromSheet']!, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      for (final w in withRows ? _workItems.where((w) => w['custom'] == true) : const <Map<String, dynamic>>[])
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              Expanded(child: Text(w['option']?.toString() ?? '')),
              if (w['custom'] == true && _canEdit) ...[
                _NumField(
                  value: _stepGrades[w['step'].toString()],
                  max: (w['max'] as num?)?.toDouble(),
                  onChanged: (v) => _stepGrades[w['step'].toString()] = v,
                ),
                const SizedBox(width: 4),
                Text('/ ${fmtPoints(w['max'] as num?)}', style: Theme.of(context).textTheme.bodySmall),
              ] else
                Text('${fmtPoints(w['points'] as num?)}${w['max'] != null ? ' / ${fmtPoints(w['max'] as num?)}' : ''}'),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                t['taskScoring.stepsTotal']!,
                style: TextStyle(fontWeight: FontWeight.w600, color: colors.primary),
              ),
            ),
            Text(
              '${fmtPoints(_points)}${_scoring.steps.isNotEmpty ? ' / ${fmtPoints(maxTotal)}' : ''}',
              style: TextStyle(fontWeight: FontWeight.w600, color: colors.primary),
            ),
          ],
        ),
      ),
    ];
  }
}

/// Port of `WorkItemsInput.vue`: the checklist's parts (ticked, and graded
/// up to their max when scored), then the kinds of work — one grade per
/// item on a graded task, otherwise kind + count + multipliers per row.
/// Edits [items] in place and calls [onChanged].
class _WorkItemsInput extends StatelessWidget {
  const _WorkItemsInput({
    required this.scoring,
    required this.items,
    required this.enabled,
    required this.t,
    required this.onChanged,
  });

  final TaskScoringSetup scoring;
  final List<WorkItemForm> items;
  final bool enabled;
  final Map<String, String> t;
  final VoidCallback onChanged;

  bool get _off => scoring.pointsOff;
  bool get _graded => !_off && scoring.graded;

  WorkItemForm? _checkItem(int ci) {
    for (final i in items) {
      if (i.check == ci) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final work = items.where((i) => !i.isCheck).toList();
    final total = roundPoints(work.fold(0.0, (s, i) => s + workItemPoints(scoring, i)));
    final checklistScored = !_off && scoring.checklist.any((c) => c.scored);
    final checklistPoints = roundPoints(items.where((i) => i.isCheck).fold(0.0, (s, i) => s + checkPoints(scoring, i)));

    Widget box(Color tint, List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.06),
        border: Border.all(color: tint.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scoring.checklist.isNotEmpty)
          box(Colors.green, [
            Text(t['taskScoring.checklistDone']!, style: const TextStyle(fontWeight: FontWeight.w500)),
            for (var ci = 0; ci < scoring.checklist.length; ci++)
              Row(
                children: [
                  Checkbox(
                    value: _checkItem(ci) != null,
                    onChanged: enabled
                        ? (on) {
                            final existing = _checkItem(ci);
                            existing == null ? items.add(WorkItemForm.check(ci)) : items.remove(existing);
                            onChanged();
                          }
                        : null,
                  ),
                  Expanded(child: Text(scoring.checklist[ci].label)),
                  if (!_off && scoring.checklist[ci].scored) ...[
                    if (_checkItem(ci) != null)
                      _NumField(
                        key: ValueKey('check-$ci'),
                        value: _checkItem(ci)!.grade,
                        max: scoring.checklist[ci].max,
                        enabled: enabled,
                        onChanged: (v) {
                          _checkItem(ci)!.grade = v;
                          onChanged();
                        },
                      ),
                    const SizedBox(width: 4),
                    Text('/ ${fmtPoints(scoring.checklist[ci].max)}', style: small),
                  ],
                ],
              ),
            if (checklistScored)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t['taskScoring.stepsTotal']!,
                        style: TextStyle(fontWeight: FontWeight.w600, color: colors.primary),
                      ),
                    ),
                    Text(
                      '${fmtPoints(checklistPoints)} / ${fmtPoints(scoring.checklistTotal)}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: colors.primary),
                    ),
                  ],
                ),
              ),
          ]),
        if (scoring.options.isNotEmpty)
          box(colors.primary, [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _graded ? t['taskScoring.gradeItems']! : t['taskScoring.workDone']!,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                if (!_off)
                  Text(
                    trf(t['taskScoring.pointsValue']!, {'n': fmtPoints(total)}),
                    style: TextStyle(fontWeight: FontWeight.w600, color: colors.primary),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (_graded)
              for (final item in work)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(_optionAt(item.option)?.label ?? '')),
                      _NumField(
                        key: ValueKey('grade-${item.option}'),
                        value: item.grade,
                        max: _optionAt(item.option)?.points,
                        enabled: enabled,
                        onChanged: (v) {
                          item.grade = v;
                          onChanged();
                        },
                      ),
                      const SizedBox(width: 4),
                      Text('/ ${fmtPoints(_optionAt(item.option)?.points)}', style: small),
                    ],
                  ),
                )
            else ...[
              for (final item in work) _workRow(context, item, small),
              if (enabled)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () {
                      items.add(WorkItemForm.work(option: firstEnabledOption(scoring)));
                      onChanged();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(t['taskScoring.addWork']!),
                  ),
                ),
            ],
          ]),
      ],
    );
  }

  ScoringOption? _optionAt(int? i) => i != null && i >= 0 && i < scoring.options.length ? scoring.options[i] : null;

  Widget _workRow(BuildContext context, WorkItemForm item, TextStyle? small) {
    return Card(
      key: ObjectKey(item),
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _optionAt(item.option) != null ? item.option : null,
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    items: [
                      for (var oi = 0; oi < scoring.options.length; oi++)
                        if (scoring.options[oi].enabled || item.option == oi)
                          DropdownMenuItem(
                            value: oi,
                            child: Text(
                              _off
                                  ? scoring.options[oi].label
                                  : '${scoring.options[oi].label} (${fmtPoints(scoring.options[oi].points)})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                    onChanged: enabled
                        ? (v) {
                            item.option = v;
                            onChanged();
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 6),
                _NumField(
                  value: item.qty.toDouble(),
                  integer: true,
                  label: t['taskScoring.qty'],
                  enabled: enabled,
                  onChanged: (v) {
                    item.qty = (v ?? 1).clamp(1, 100).toInt();
                    onChanged();
                  },
                ),
                if (!_off)
                  SizedBox(
                    width: 48,
                    child: Text(fmtPoints(workItemPoints(scoring, item)), textAlign: TextAlign.center, style: small),
                  ),
                if (enabled)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: t['taskScoring.delete'],
                    onPressed: () {
                      items.remove(item);
                      onChanged();
                    },
                  ),
              ],
            ),
            if (!_off && scoring.modifiers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (var mi = 0; mi < scoring.modifiers.length; mi++)
                      FilterChip(
                        label: Text('${scoring.modifiers[mi].label} ×${fmtPoints(scoring.modifiers[mi].factor)}'),
                        selected: item.modifiers.contains(mi),
                        onSelected: enabled
                            ? (on) {
                                on ? item.modifiers.add(mi) : item.modifiers.remove(mi);
                                onChanged();
                              }
                            : null,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small number box that keeps its own text while typing (so "2." isn't
/// rewritten mid-edit) and reports the parsed value, capped at [max].
class _NumField extends StatefulWidget {
  const _NumField({
    super.key,
    required this.value,
    required this.onChanged,
    this.max,
    this.enabled = true,
    this.integer = false,
    this.label,
  });

  final double? value;
  final double? max;
  final bool enabled;
  final bool integer;
  final String? label;
  final ValueChanged<double?> onChanged;

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _controller = TextEditingController(text: fmtPoints(widget.value));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: TextField(
        controller: _controller,
        enabled: widget.enabled,
        keyboardType: TextInputType.numberWithOptions(decimal: !widget.integer),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(widget.integer ? r'[0-9]' : r'[0-9.]'))],
        textAlign: TextAlign.center,
        decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), hintText: widget.label),
        onChanged: (text) {
          var v = double.tryParse(text);
          if (v != null && widget.max != null && v > widget.max!) v = widget.max;
          widget.onChanged(v);
        },
      ),
    );
  }
}
