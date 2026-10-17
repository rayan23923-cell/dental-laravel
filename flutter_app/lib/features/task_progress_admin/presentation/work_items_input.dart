import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../domain/task_scoring.dart';

/// The work done on a case (the web's `WorkItemsInput.vue`, 2026-10-17):
/// checklist parts to tick (graded ones take a grade up to their max), and
/// kinds of work with how many and any multipliers, or one grade per item
/// on a graded task. Shows the points they add up to unless points are
/// switched off. Edits [items] in place and calls [onChanged].
class WorkItemsInput extends ConsumerWidget {
  const WorkItemsInput({super.key, required this.scoring, required this.items, required this.onChanged, this.enabled = true});

  final TaskScoringSetup scoring;
  final List<WorkItemDraft> items;
  final VoidCallback onChanged;
  final bool enabled;

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '${(v * 100).round() / 100}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final s = scoring;
    final work = items.where((i) => !i.isCheck).toList();
    final total = (work.fold<double>(0, (sum, i) => sum + workItemPoints(s, i)) * 100).round() / 100;

    WorkItemDraft? checkItem(int ci) {
      for (final i in items) {
        if (i.check == ci) return i;
      }
      return null;
    }

    final checklistPoints = s.checklist.asMap().entries.fold<double>(0, (sum, e) {
      final item = checkItem(e.key);
      return e.value.scored && item != null ? sum + (item.grade ?? 0).clamp(0, e.value.max) : sum;
    });
    final checklistMax = s.checklist.where((c) => c.scored).fold<double>(0, (sum, c) => sum + c.max);

    void toggleCheck(int ci) {
      final existing = checkItem(ci);
      existing == null ? items.add(WorkItemDraft.check(check: ci)) : items.remove(existing);
      onChanged();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.checklist.isNotEmpty)
          _Box(
            color: Colors.green,
            title: t['taskScoring.checklistDone']!,
            children: [
              for (var ci = 0; ci < s.checklist.length; ci++)
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: checkItem(ci) != null,
                        onChanged: enabled ? (_) => toggleCheck(ci) : null,
                        title: Text(s.checklist[ci].label),
                      ),
                    ),
                    if (!s.pointsOff && s.checklist[ci].scored && checkItem(ci) != null)
                      _GradeField(
                        value: checkItem(ci)!.grade,
                        max: s.checklist[ci].max,
                        enabled: enabled,
                        onChanged: (v) {
                          checkItem(ci)!.grade = v;
                          onChanged();
                        },
                      )
                    else if (!s.pointsOff && s.checklist[ci].scored)
                      Text('/ ${_fmt(s.checklist[ci].max)}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              if (s.checklistScored)
                _TotalRow(label: t['taskScoring.stepsTotal']!, value: '${_fmt(checklistPoints)} / ${_fmt(checklistMax)}'),
            ],
          ),
        if (s.checklist.isNotEmpty && s.options.isNotEmpty) const SizedBox(height: 12),
        if (s.options.isNotEmpty)
          _Box(
            color: Colors.indigo,
            title: s.isGraded ? t['taskScoring.gradeItems']! : t['taskScoring.workDone']!,
            badge: s.pointsOff ? null : trf(t['taskScoring.pointsValue']!, {'n': _fmt(total)}),
            children: [
              if (s.isGraded)
                for (final item in work)
                  Row(
                    children: [
                      Expanded(child: Text(item.option! < s.options.length ? s.options[item.option!].label : '—')),
                      _GradeField(
                        value: item.grade,
                        max: item.option! < s.options.length ? s.options[item.option!].points : 0,
                        enabled: enabled,
                        onChanged: (v) {
                          item.grade = v;
                          onChanged();
                        },
                      ),
                    ],
                  )
              else ...[
                for (final item in work)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                isExpanded: true,
                                initialValue: item.option,
                                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                items: [
                                  for (var oi = 0; oi < s.options.length; oi++)
                                    if (s.options[oi].enabled || item.option == oi)
                                      DropdownMenuItem(
                                        value: oi,
                                        child: Text(
                                          s.pointsOff ? s.options[oi].label : '${s.options[oi].label} (${_fmt(s.options[oi].points)})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                ],
                                onChanged: enabled
                                    ? (v) {
                                        if (v == null) return;
                                        item.option = v;
                                        onChanged();
                                      }
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 64,
                              child: TextFormField(
                                key: ValueKey('qty-${identityHashCode(item)}'),
                                initialValue: '${item.qty}',
                                enabled: enabled,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), labelText: t['taskScoring.qty']),
                                onChanged: (v) {
                                  item.qty = (int.tryParse(v) ?? 1).clamp(1, 100);
                                  onChanged();
                                },
                              ),
                            ),
                            if (!s.pointsOff)
                              SizedBox(width: 48, child: Text(_fmt(workItemPoints(s, item)), textAlign: TextAlign.center)),
                            IconButton(
                              tooltip: t['tasksAdmin.delete'],
                              icon: const Icon(Icons.close),
                              onPressed: enabled
                                  ? () {
                                      items.remove(item);
                                      onChanged();
                                    }
                                  : null,
                            ),
                          ],
                        ),
                        if (!s.pointsOff && s.modifiers.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            children: [
                              for (var mi = 0; mi < s.modifiers.length; mi++)
                                FilterChip(
                                  label: Text('${s.modifiers[mi].label} ×${_fmt(s.modifiers[mi].factor)}'),
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
                      ],
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: enabled
                        ? () {
                            items.add(WorkItemDraft.work(option: s.firstEnabledOption));
                            onChanged();
                          }
                        : null,
                    icon: const Icon(Icons.add),
                    label: Text(t['taskScoring.addWork']!),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.color, required this.title, required this.children, this.badge});

  final MaterialColor color;
  final String title;
  final String? badge;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.12 : 0.06),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                  child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// A grade up to [max], in half points.
class _GradeField extends StatelessWidget {
  const _GradeField({required this.value, required this.max, required this.onChanged, this.enabled = true});

  final double? value;
  final double max;
  final ValueChanged<double?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 72,
          child: TextFormField(
            initialValue: value == null ? '' : WorkItemsInput._fmt(value!),
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
            textAlign: TextAlign.center,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            onChanged: (v) {
              final parsed = double.tryParse(v);
              onChanged(parsed == null ? null : parsed.clamp(0, max).toDouble());
            },
          ),
        ),
        const SizedBox(width: 4),
        Text('/ ${WorkItemsInput._fmt(max)}', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
