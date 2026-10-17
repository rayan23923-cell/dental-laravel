import 'package:flutter/material.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/widgets/numeric_input.dart';
import '../domain/task_scoring.dart';

/// Points setup of one task (2026-10-17), the app's twin of the web's
/// `ScoringEditor.vue`: how it is measured, the points target, its
/// weight, the case-sheet steps (reordered by dragging their handle,
/// switched on or off, more added by hand), the kinds of work (switched
/// on or off) with their points, graded checklist parts and the optional
/// multipliers. Edits [scoring] in place; with points switched off only
/// the points boxes and totals are hidden, the lists stay.
class ScoringEditor extends StatefulWidget {
  const ScoringEditor({super.key, required this.scoring, required this.t, this.onChanged});

  final TaskScoringSetup scoring;
  final Map<String, String> t;

  /// Called after every edit, for a parent showing a summary of the setup.
  final VoidCallback? onChanged;

  @override
  State<ScoringEditor> createState() => _ScoringEditorState();
}

class _ScoringEditorState extends State<ScoringEditor> {
  TaskScoringSetup get s => widget.scoring;
  Map<String, String> get t => widget.t;
  bool get off => s.pointsOff;

  void _edit(VoidCallback change) {
    setState(change);
    widget.onChanged?.call();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? t['tasksAdmin.requiredField'] : null;

  Widget _label(Object item, String value, String hint, ValueChanged<String> onChanged, {int? maxLength}) => TextFormField(
        key: ObjectKey(item),
        initialValue: value,
        minLines: 1,
        maxLines: 4,
        maxLength: maxLength,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          counterText: '',
          border: const OutlineInputBorder(),
        ),
        validator: _required,
        onChanged: (v) {
          onChanged(v);
          widget.onChanged?.call();
        },
      );

  Widget _number(
    Object key,
    num? value,
    ValueChanged<double?> onChanged, {
    String? label,
    String? hint,
    bool enabled = true,
    bool required = true,
    double width = 84,
  }) =>
      SizedBox(
        width: width,
        child: TextFormField(
          key: ValueKey(key),
          initialValue: fmtPoints(value),
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalOnly,
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, border: const OutlineInputBorder()),
          validator: required && enabled ? (v) => double.tryParse(v?.trim() ?? '') == null ? t['tasksAdmin.requiredField'] : null : null,
          onChanged: (v) => _edit(() => onChanged(double.tryParse(v.trim()))),
        ),
      );

  Widget _total(double value) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Expanded(child: Text(t['taskScoring.stepsTotal']!, style: TextStyle(fontWeight: FontWeight.w600, color: colors.onPrimaryContainer))),
          Text(fmtPoints(value), style: TextStyle(fontWeight: FontWeight.w600, color: colors.onPrimaryContainer)),
        ],
      ),
    );
  }

  Widget _header(String title, {String? addLabel, VoidCallback? onAdd}) => Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
          if (onAdd != null)
            TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add, size: 18), label: Text(addLabel ?? '')),
        ],
      );

  Widget _delete(VoidCallback onPressed) => IconButton(
        icon: const Icon(Icons.close, size: 18),
        tooltip: t['taskScoring.delete'],
        visualDensity: VisualDensity.compact,
        onPressed: () => _edit(onPressed),
      );

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!off) ...[
          DropdownButtonFormField<String>(
            initialValue: TaskScoringSetupMeasures.all.contains(s.measure) ? s.measure : 'count',
            decoration: InputDecoration(labelText: t['taskScoring.measure'], isDense: true, border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: 'count', child: Text(t['taskScoring.measureCount']!)),
              DropdownMenuItem(value: 'points', child: Text(t['taskScoring.measurePoints']!)),
              DropdownMenuItem(value: 'both', child: Text(t['taskScoring.measureBoth']!)),
            ],
            onChanged: (v) => _edit(() => s.measure = v ?? 'count'),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            if (!off) ...[
              Expanded(
                child: _number(
                  'min_points-${s.measure}-${s.steps.isEmpty}',
                  s.minPoints,
                  (v) => s.minPoints = v,
                  label: t['taskScoring.minPoints'],
                  enabled: s.measure != 'count' && s.steps.isEmpty,
                  required: false,
                  width: double.infinity,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _number(
                'weight',
                s.weight,
                (v) => s.weight = v,
                label: t['taskScoring.weight'],
                hint: t['taskScoring.weightAuto'],
                required: false,
                width: double.infinity,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (s.steps.isNotEmpty) ..._steps(muted) else ..._options(muted),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: s.endo,
          title: Text(t['taskScoring.endoHint']!),
          onChanged: (v) => _edit(() => s.endo = v ?? false),
        ),
        ..._checklist(muted),
        if (!off) ..._modifiers(),
      ],
    );
  }

  /// Steps can be reordered by dragging their handle (2026-10-16 on the
  /// web); grades follow each step's key, not its place.
  List<Widget> _steps(TextStyle? muted) => [
        Text(t['taskScoring.steps']!, style: Theme.of(context).textTheme.titleSmall),
        Text(t['taskScoring.stepsHint']!, style: muted),
        const SizedBox(height: 4),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) => _edit(() => s.steps.insert(to, s.steps.removeAt(from))),
          children: [
            for (var i = 0; i < s.steps.length; i++)
              _stepRow(i, s.steps[i]),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => _edit(() => s.steps.add(ScoringStep(
                  key: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                  custom: true,
                ))),
            icon: const Icon(Icons.add, size: 18),
            label: Text(t['taskScoring.addStep']!),
          ),
        ),
        if (!off) _total(s.stepsTotal),
        const SizedBox(height: 8),
      ];

  Widget _stepRow(int i, ScoringStep st) => Material(
        key: ObjectKey(st),
        color: Colors.transparent,
        child: Opacity(
          opacity: st.enabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: i,
                  child: Tooltip(
                    message: t['taskScoring.dragStep']!,
                    child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.drag_indicator)),
                  ),
                ),
                Checkbox(value: st.enabled, onChanged: (v) => _edit(() => st.enabled = v ?? true)),
                Expanded(
                  child: st.custom
                      ? _label(st, st.label, t['taskScoring.stepLabel']!, (v) => st.label = v, maxLength: 100)
                      : Text(st.label),
                ),
                if (!off) ...[
                  const SizedBox(width: 6),
                  _number(('step', st), st.max, (v) => st.max = v ?? 0, label: t['taskScoring.stepMax'], enabled: st.enabled),
                ],
                if (st.custom) _delete(() => s.steps.remove(st)),
              ],
            ),
          ),
        ),
      );

  List<Widget> _options(TextStyle? muted) => [
        _header(
          t['taskScoring.options']!,
          addLabel: t['taskScoring.addOption'],
          onAdd: () => _edit(() => s.options.add(ScoringOption())),
        ),
        for (final o in s.options)
          Opacity(
            key: ObjectKey(o),
            opacity: o.enabled ? 1 : 0.5,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Checkbox(value: o.enabled, onChanged: (v) => _edit(() => o.enabled = v ?? true)),
                  Expanded(child: _label(o, o.label, t['taskScoring.optionLabel']!, (v) => o.label = v, maxLength: 100)),
                  if (!off) ...[
                    const SizedBox(width: 6),
                    _number(('option', o), o.points, (v) => o.points = v ?? 0),
                  ],
                  _delete(() => s.options.remove(o)),
                ],
              ),
            ),
          ),
        if (s.options.isEmpty)
          Text(t['taskScoring.noOptions']!, style: muted)
        else if (!off)
          _total(s.optionsTotal),
        if (s.options.isNotEmpty && !off)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: s.graded,
            title: Text(t['taskScoring.graded']!),
            onChanged: (v) => _edit(() => s.graded = v ?? false),
          ),
        const SizedBox(height: 4),
      ];

  /// Checklist parts may carry a grade (2026-10-16 on the web), totalled below the list.
  List<Widget> _checklist(TextStyle? muted) => [
        _header(
          t['taskScoring.checklist']!,
          addLabel: t['taskScoring.addCheck'],
          onAdd: () => _edit(() => s.checklist.add(ScoringCheck())),
        ),
        for (final c in s.checklist)
          Padding(
            key: ObjectKey(c),
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _label(c, c.label, t['taskScoring.checkLabel']!, (v) => c.label = v, maxLength: 150)),
                    _delete(() => s.checklist.remove(c)),
                  ],
                ),
                if (!off)
                  Row(
                    children: [
                      Checkbox(
                        value: c.scored,
                        onChanged: (v) => _edit(() {
                          c.scored = v ?? false;
                          if (c.scored && c.max == null) c.max = 10;
                        }),
                      ),
                      Text(t['taskScoring.checkScored']!),
                      const SizedBox(width: 8),
                      if (c.scored) _number(('check', c), c.max, (v) => c.max = v, label: t['taskScoring.stepMax']),
                    ],
                  ),
              ],
            ),
          ),
        if (s.checklist.isNotEmpty) Text(t['taskScoring.checklistHint']!, style: muted),
        if (!off && s.checklist.any((c) => c.scored)) _total(s.checklistTotal),
        const SizedBox(height: 8),
      ];

  List<Widget> _modifiers() => [
        _header(
          t['taskScoring.modifiers']!,
          addLabel: t['taskScoring.addModifier'],
          onAdd: () => _edit(() => s.modifiers.add(ScoringModifier())),
        ),
        for (final m in s.modifiers)
          Padding(
            key: ObjectKey(m),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(child: _label(m, m.label, t['taskScoring.modifierLabel']!, (v) => m.label = v, maxLength: 100)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('×')),
                _number(('modifier', m), m.factor, (v) => m.factor = v ?? 1),
                _delete(() => s.modifiers.remove(m)),
              ],
            ),
          ),
      ];
}

/// The measures `TaskScoring::MEASURES` accepts.
abstract final class TaskScoringSetupMeasures {
  static const all = ['count', 'points', 'both'];
}

/// "تفعيل النقاط" switch + editor + department pass %, used by the edit
/// form (web Tasks/Edit.vue's box).
class ScoringSection extends StatelessWidget {
  const ScoringSection({
    super.key,
    required this.scoring,
    required this.usePoints,
    required this.onUsePoints,
    required this.passPercentController,
    required this.t,
  });

  final TaskScoringSetup scoring;
  final bool usePoints;
  final ValueChanged<bool> onUsePoints;
  final TextEditingController passPercentController;
  final Map<String, String> t;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: usePoints,
              title: Text(t['taskScoring.enablePoints']!),
              onChanged: onUsePoints,
            ),
            ScoringEditor(scoring: scoring, t: t),
            const SizedBox(height: 8),
            PassPercentField(controller: passPercentController, t: t),
          ],
        ),
      ),
    );
  }
}

class PassPercentField extends StatelessWidget {
  const PassPercentField({super.key, required this.controller, required this.t});

  final TextEditingController controller;
  final Map<String, String> t;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: decimalOnly,
        decoration: InputDecoration(labelText: t['taskScoring.passPercent'], isDense: true, border: const OutlineInputBorder()),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return null;
          final n = double.tryParse(v.trim());
          return n == null || n < 0 || n > 100 ? '0 - 100' : null;
        },
      );
}

/// Chips summing up a table row's setup (web Tasks/Create.vue's row badges).
class ScoringSummaryChips extends StatelessWidget {
  const ScoringSummaryChips({super.key, required this.row, required this.t});

  final ScoringTemplateRow row;
  final Map<String, String> t;

  @override
  Widget build(BuildContext context) {
    final s = row.scoring;
    if (s == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    Widget chip(String text, {Color? bg, Color? fg}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: bg ?? colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
          child: Text(text, style: TextStyle(fontSize: 12, color: fg ?? colors.onSurfaceVariant)),
        );
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (row.pointsOn && (s.minPoints ?? 0) > 0)
          chip(trf(t['taskScoring.pointsValue']!, {'n': fmtPoints(s.minPoints)}), bg: colors.primaryContainer, fg: colors.onPrimaryContainer),
        if ((s.weight ?? 0) > 0) chip('${fmtPoints(s.weight)}%', bg: Colors.amber.shade100, fg: Colors.amber.shade900),
        if (s.steps.isNotEmpty) chip(trf(t['taskScoring.stepsCount']!, {'n': s.steps.where((x) => x.enabled).length})),
        for (final o in s.options.where((x) => x.enabled)) chip(row.pointsOn ? '${o.label} ${fmtPoints(o.points)}' : o.label),
        if (s.endo) chip(t['taskScoring.rootFilling']!, bg: colors.primary, fg: colors.onPrimary),
        for (final c in s.checklist) chip('✓ ${c.label}', bg: Colors.green.shade100, fg: Colors.green.shade900),
      ],
    );
  }
}
