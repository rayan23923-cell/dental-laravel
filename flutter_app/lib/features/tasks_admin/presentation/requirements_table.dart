import 'package:flutter/material.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/widgets/numeric_input.dart';
import '../domain/task_scoring.dart';
import 'scoring_editor.dart';

/// A case-sheet type's requirements table in the add-task form
/// (2026-10-17, the app's twin of the web's Tasks/Create.vue table): every
/// enabled row becomes its own task with its count, case sheet and points
/// setup, and the department gets the pass percentage.
class RequirementsTable extends StatefulWidget {
  const RequirementsTable({
    super.key,
    required this.rows,
    required this.caseSheetTypes,
    required this.passPercentController,
    required this.t,
  });

  final List<ScoringTemplateRow> rows;
  final List<LookupItem> caseSheetTypes;
  final TextEditingController passPercentController;
  final Map<String, String> t;

  @override
  State<RequirementsTable> createState() => _RequirementsTableState();
}

class _RequirementsTableState extends State<RequirementsTable> {
  final _open = <ScoringTemplateRow>{};

  Map<String, String> get t => widget.t;

  /// Switching a row's points off only hides the points and totals (web 2026-10-16).
  void _togglePoints(ScoringTemplateRow row, bool on) => setState(() {
        row.scoring ??= TaskScoringSetup();
        row.scoring!.pointsOff = !on;
      });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.outline);
    return Card(
      margin: EdgeInsets.zero,
      color: colors.primaryContainer.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t['taskScoring.table']!, style: Theme.of(context).textTheme.titleMedium),
            Text(t['taskScoring.tableHint']!, style: muted),
            const SizedBox(height: 8),
            for (final row in widget.rows) _row(row),
            const SizedBox(height: 8),
            PassPercentField(controller: widget.passPercentController, t: t),
          ],
        ),
      ),
    );
  }

  Widget _row(ScoringTemplateRow row) {
    final sheetIds = widget.caseSheetTypes.map((c) => c.id).toSet();
    return Card(
      key: ObjectKey(row),
      margin: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: row.enabled ? 1 : 0.55,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(value: row.enabled, onChanged: (v) => setState(() => row.enabled = v ?? false)),
                  Expanded(
                    child: TextFormField(
                      initialValue: row.title,
                      enabled: row.enabled,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      validator: (v) => row.enabled && (v == null || v.trim().isEmpty) ? t['tasksAdmin.requiredField'] : null,
                      onChanged: (v) => row.title = v,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(t['taskScoring.cases']!),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextFormField(
                      initialValue: '${row.requiredCount}',
                      enabled: row.enabled,
                      keyboardType: TextInputType.number,
                      inputFormatters: digitsOnly,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      validator: (v) => row.enabled && (int.tryParse(v?.trim() ?? '') ?? 0) < 1 ? t['tasksAdmin.requiredField'] : null,
                      onChanged: (v) => row.requiredCount = int.tryParse(v.trim()) ?? 0,
                    ),
                  ),
                ],
              ),
              if (row.enabled) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: sheetIds.contains(row.caseSheetTypeId) ? row.caseSheetTypeId : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t['taskScoring.rowSheet'], isDense: true, border: const OutlineInputBorder()),
                  items: [
                    for (final c in widget.caseSheetTypes)
                      DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => row.caseSheetTypeId = v),
                ),
              ],
              const SizedBox(height: 6),
              ScoringSummaryChips(row: row, t: t),
              if (row.enabled)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  initiallyExpanded: _open.contains(row),
                  onExpansionChanged: (open) => open ? _open.add(row) : _open.remove(row),
                  title: Text(t['taskScoring.pointsSetup']!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: row.pointsOn,
                      title: Text(t['taskScoring.enablePoints']!),
                      onChanged: (on) => _togglePoints(row, on),
                    ),
                    if (row.scoring != null) ScoringEditor(scoring: row.scoring!, t: t, onChanged: () => setState(() {})),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
