/// The work done on a case (web `WorkItemsInput.vue` / `workItems.js`,
/// 2026-10-17): a kind of work with how many and its multipliers, a
/// graded item, or a ticked checklist part. Indexes point into the task's
/// own [TaskScoringSetup]; the server recomputes the points from it
/// (`TaskScoring::resolveWorkItems()`).
library;

import 'task_scoring.dart';

class WorkItemForm {
  WorkItemForm.work({required int this.option, this.qty = 1, this.grade, List<int>? modifiers})
      : check = null,
        modifiers = modifiers ?? [];
  WorkItemForm.check(int this.check, {this.grade})
      : option = null,
        qty = 1,
        modifiers = [];

  int? option;
  final int? check;
  int qty;
  double? grade;
  final List<int> modifiers;

  bool get isCheck => check != null;

  Map<String, dynamic> toJson() => isCheck
      ? {'check': check, 'grade': grade}
      : {'option': option, 'qty': qty, 'grade': grade, 'modifiers': modifiers};
}

/// Stored items keep labels; maps them back to the task's option,
/// multiplier and checklist indexes. A graded task lists every enabled
/// item once; a plain one starts with one row (port of `workItemsToForm`).
List<WorkItemForm> workItemsToForm(TaskScoringSetup? scoring, List<dynamic>? stored) {
  final s = scoring ?? TaskScoringSetup();
  final items = <WorkItemForm>[];
  for (final raw in stored ?? const []) {
    if (raw is! Map) continue;
    final label = raw['option']?.toString();
    final grade = double.tryParse(raw['grade']?.toString() ?? '');
    if (raw['check'] == true) {
      final ci = s.checklist.indexWhere((c) => c.label == label);
      if (ci >= 0) items.add(WorkItemForm.check(ci, grade: grade));
    } else if (raw['step'] == null) {
      final oi = s.options.indexWhere((o) => o.label == label);
      if (oi < 0) continue;
      final mods = [
        for (final m in (raw['modifiers'] as List<dynamic>? ?? const []))
          s.modifiers.indexWhere((x) => x.label == m.toString()),
      ].where((i) => i >= 0).toList();
      items.add(WorkItemForm.work(option: oi, qty: (raw['qty'] as num?)?.toInt() ?? 1, grade: grade, modifiers: mods));
    }
  }
  if (s.graded) {
    for (var i = 0; i < s.options.length; i++) {
      if (s.options[i].enabled && !items.any((w) => w.option == i)) items.add(WorkItemForm.work(option: i));
    }
    items.sort((a, b) => (a.option ?? -1).compareTo(b.option ?? -1));
  } else if (s.options.isNotEmpty && !items.any((w) => !w.isCheck)) {
    items.add(WorkItemForm.work(option: firstEnabledOption(s)));
  }
  return items;
}

int firstEnabledOption(TaskScoringSetup s) {
  final i = s.options.indexWhere((o) => o.enabled);
  return i < 0 ? 0 : i;
}

/// What one kind of work adds up to, as the server will count it.
double workItemPoints(TaskScoringSetup s, WorkItemForm item) {
  if (item.isCheck || item.option == null || item.option! >= s.options.length) return 0;
  final option = s.options[item.option!];
  final factor = item.modifiers.fold<double>(1, (f, m) => f * (m < s.modifiers.length ? s.modifiers[m].factor : 1));
  final graded = !s.pointsOff && s.graded;
  final base = graded ? ((item.grade ?? 0) < option.points ? (item.grade ?? 0) : option.points) : option.points * item.qty;
  return roundPoints(base * factor);
}

/// A ticked graded part's points, up to its max.
double checkPoints(TaskScoringSetup s, WorkItemForm item) {
  final c = item.check;
  if (c == null || c >= s.checklist.length || !s.checklist[c].scored) return 0;
  final max = s.checklist[c].max ?? 0;
  final grade = (item.grade ?? 0).clamp(0, max).toDouble();
  return grade;
}
