import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../task_progress_admin/domain/task_scoring.dart';
import '../../task_progress_admin/presentation/work_items_input.dart';

/// The linked task's points on its case sheet (the web's `TaskWorkPanel.vue`,
/// 2026-10-17): the same work, grades and checklist the task-progress
/// dialogs record, read from and saved to the task instance, so both always
/// agree. A task graded by the sheet's own steps shows what they add up to.
/// Staff who may finish tasks edit it; the doctor sees it.
class TaskWorkPanel extends ConsumerStatefulWidget {
  const TaskWorkPanel({super.key, required this.taskInstanceId});

  final int taskInstanceId;

  @override
  ConsumerState<TaskWorkPanel> createState() => _TaskWorkPanelState();
}

class _TaskWorkPanelState extends ConsumerState<TaskWorkPanel> {
  Map<String, dynamic>? _data;
  TaskScoringSetup _scoring = const TaskScoringSetup();
  List<WorkItemDraft> _items = [];

  /// Grades of steps added by hand, keyed by step; the sheet's own steps
  /// are graded on the sheet.
  final Map<String, double?> _stepGrades = {};
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
      if (!mounted) return;
      final scoring = TaskScoringSetup.fromJson(d['scoring'] as Map<String, dynamic>?);
      setState(() {
        _data = d;
        _scoring = scoring;
        _items = d['from_sheet'] == true ? [] : workItemsToDrafts(scoring, d['work_items'] as List<dynamic>?);
        _stepGrades
          ..clear()
          ..addEntries(_workItems(d).where((w) => w['custom'] == true).map((w) => MapEntry('${w['step']}', _num(w['points']))));
      });
    } catch (_) {
      // No panel when it can't load, as on the web.
    }
  }

  static List<Map<String, dynamic>> _workItems(Map<String, dynamic>? d) =>
      (d?['work_items'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();

  static double? _num(Object? v) => v == null ? null : double.tryParse('$v');

  static String _fmt(Object? v) {
    final n = _num(v);
    if (n == null) return '—';
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : '${(n * 100).round() / 100}';
  }

  Future<void> _save() async {
    final t = ref.read(translationsProvider);
    setState(() {
      _saving = true;
      _message = _error = null;
    });
    try {
      final fromSheet = _data?['from_sheet'] == true;
      final body = fromSheet
          ? {'step_grades': _stepGrades}
          : {'work_items': _items.map((w) => w.toJson()).toList()};
      final d = await ref.read(apiClientProvider).putJson(_path, body: body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _data = {...?_data, 'work_items': d['work_items'], 'points': d['points']};
        _message = t['taskScoring.saved'];
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.userMessage : t['taskScoring.saveFailed']);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final fromSheet = d?['from_sheet'] == true;
    if (d == null || !(fromSheet || _scoring.hasWork)) return const SizedBox.shrink();
    final t = ref.watch(translationsProvider);
    final canEdit = d['can_edit'] == true;
    final points = d['points'];
    final rows = _workItems(d);
    final stepsMax = rows.fold<double>(0, (sum, w) => sum + (_num(w['max']) ?? 0));

    Widget saveRow() => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(onPressed: _saving ? null : _save, child: Text(t['taskScoring.savePoints']!)),
              if (_message != null) Text(_message!, style: const TextStyle(color: Colors.green)),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['taskScoring.sheetPanel']!, style: Theme.of(context).textTheme.titleMedium),
                      if (d['title'] != null) Text('${d['title']}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (points != null)
                  Chip(
                    label: Text(trf(t['taskScoring.pointsValue']!, {'n': _fmt(points)}), style: const TextStyle(color: Colors.white)),
                    backgroundColor: Colors.indigo,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (fromSheet) ...[
              Text(t['taskScoring.fromSheet']!, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              for (final w in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text('${w['option'] ?? ''}')),
                      if (w['custom'] == true && canEdit)
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            initialValue: _stepGrades['${w['step']}'] == null ? '' : _fmt(_stepGrades['${w['step']}']),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                            onChanged: (v) => _stepGrades['${w['step']}'] = double.tryParse(v),
                          ),
                        )
                      else
                        Text(_fmt(w['points'])),
                      if (w['max'] != null) Text(' / ${_fmt(w['max'])}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              const Divider(),
              Row(
                children: [
                  Expanded(child: Text(t['taskScoring.stepsTotal']!, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text('${_fmt(points)} / ${_fmt(stepsMax)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              if (canEdit && rows.any((w) => w['custom'] == true)) saveRow(),
            ] else ...[
              WorkItemsInput(scoring: _scoring, items: _items, enabled: canEdit, onChanged: () => setState(() {})),
              if (!canEdit)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(t['taskScoring.supervisorOnly']!, style: Theme.of(context).textTheme.bodySmall),
                )
              else
                saveRow(),
            ],
          ],
        ),
      ),
    );
  }
}
