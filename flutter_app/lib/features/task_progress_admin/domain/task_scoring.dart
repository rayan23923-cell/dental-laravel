/// A task's points setup (`tasks.scoring`, see the server's
/// `App\Support\TaskScoring`), as far as recording a case's work needs it
/// (2026-10-17, the web's `WorkItemsInput.vue` in the app): kinds of work
/// with their points, multipliers, checklist parts, graded items, and the
/// points switch.
class TaskScoringSetup {
  const TaskScoringSetup({
    this.options = const [],
    this.modifiers = const [],
    this.checklist = const [],
    this.graded = false,
    this.pointsOff = false,
    this.hasSteps = false,
  });

  factory TaskScoringSetup.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TaskScoringSetup();
    List<Map<String, dynamic>> list(String key) =>
        (json[key] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    return TaskScoringSetup(
      options: list('options').map(WorkOption.fromJson).toList(),
      modifiers: list('modifiers').map(WorkModifier.fromJson).toList(),
      checklist: list('checklist').map(ChecklistPart.fromJson).toList(),
      graded: json['graded'] == true,
      pointsOff: json['points_off'] == true,
      hasSteps: list('steps').any((s) => s['enabled'] == true),
    );
  }

  final List<WorkOption> options;
  final List<WorkModifier> modifiers;
  final List<ChecklistPart> checklist;
  final bool graded;

  /// Points switched off (2026-10-16): items are still recorded, without
  /// points or totals.
  final bool pointsOff;

  /// Graded by its case sheet's steps (prosthodontics): the points come
  /// from the sheet, not from work recorded here.
  final bool hasSteps;

  /// Whether a case of this task has work to record.
  bool get hasWork => options.isNotEmpty || checklist.isNotEmpty;

  bool get isGraded => !pointsOff && graded;

  bool get checklistScored => !pointsOff && checklist.any((c) => c.scored);

  int get firstEnabledOption {
    final i = options.indexWhere((o) => o.enabled);
    return i < 0 ? 0 : i;
  }
}

class WorkOption {
  const WorkOption({required this.label, required this.points, this.enabled = true});

  factory WorkOption.fromJson(Map<String, dynamic> json) => WorkOption(
        label: '${json['label'] ?? ''}',
        points: _num(json['points']),
        enabled: json['enabled'] != false,
      );

  final String label;
  final double points;
  final bool enabled;
}

class WorkModifier {
  const WorkModifier({required this.label, required this.factor});

  factory WorkModifier.fromJson(Map<String, dynamic> json) =>
      WorkModifier(label: '${json['label'] ?? ''}', factor: _num(json['factor'], 1));

  final String label;
  final double factor;
}

class ChecklistPart {
  const ChecklistPart({required this.label, this.scored = false, this.max = 0});

  factory ChecklistPart.fromJson(Map<String, dynamic> json) =>
      ChecklistPart(label: '${json['label'] ?? ''}', scored: json['scored'] == true, max: _num(json['max']));

  final String label;
  final bool scored;
  final double max;
}

/// One row being edited: a kind of work ([option] index, [qty], [modifiers]
/// indexes, [grade] when graded) or a ticked checklist part ([check] index,
/// [grade] when that part is scored). The server recomputes the points.
class WorkItemDraft {
  WorkItemDraft.work({required int this.option, this.qty = 1, List<int>? modifiers, this.grade})
      : check = null,
        modifiers = modifiers ?? [];

  WorkItemDraft.check({required int this.check, this.grade})
      : option = null,
        qty = 1,
        modifiers = [];

  int? option;
  final int? check;
  int qty;
  final List<int> modifiers;
  double? grade;

  bool get isCheck => check != null;

  Map<String, dynamic> toJson() => isCheck
      ? {'check': check, if (grade != null) 'grade': grade}
      : {'option': option, 'qty': qty, 'modifiers': modifiers, if (grade != null) 'grade': grade};
}

/// Stored work items keep labels; maps them back to the setup's indexes
/// (the web's `workItemsToForm`). A graded task lists every item once; a
/// plain one starts with one row.
List<WorkItemDraft> workItemsToDrafts(TaskScoringSetup s, List<dynamic>? stored) {
  final items = <WorkItemDraft>[];
  for (final raw in stored ?? const []) {
    if (raw is! Map<String, dynamic>) continue;
    final label = '${raw['option'] ?? ''}';
    final grade = raw['grade'] == null ? null : _num(raw['grade']);
    if (raw['check'] == true) {
      final ci = s.checklist.indexWhere((c) => c.label == label);
      if (ci >= 0) items.add(WorkItemDraft.check(check: ci, grade: grade));
    } else {
      final oi = s.options.indexWhere((o) => o.label == label);
      if (oi < 0) continue;
      final mods = (raw['modifiers'] as List<dynamic>? ?? const [])
          .map((m) => s.modifiers.indexWhere((x) => x.label == '$m'))
          .where((i) => i >= 0)
          .toList();
      items.add(WorkItemDraft.work(option: oi, qty: (raw['qty'] as num?)?.toInt() ?? 1, modifiers: mods, grade: grade));
    }
  }
  if (s.graded) {
    for (var i = 0; i < s.options.length; i++) {
      if (s.options[i].enabled && !items.any((w) => w.option == i)) items.add(WorkItemDraft.work(option: i));
    }
    items.sort((a, b) => (a.option ?? -1).compareTo(b.option ?? -1));
  } else if (s.options.isNotEmpty && !items.any((w) => !w.isCheck)) {
    items.add(WorkItemDraft.work(option: s.firstEnabledOption));
  }
  return items;
}

/// The points one kind-of-work row adds up to, as the server computes it.
double workItemPoints(TaskScoringSetup s, WorkItemDraft item) {
  final option = item.option == null || item.option! >= s.options.length ? null : s.options[item.option!];
  if (option == null || s.pointsOff) return 0;
  final factor = item.modifiers.fold<double>(
    1,
    (f, m) => f * (m < s.modifiers.length ? s.modifiers[m].factor : 1),
  );
  final base = s.isGraded ? (item.grade ?? 0).clamp(0, option.points).toDouble() : option.points * (item.qty < 1 ? 1 : item.qty);
  return (base * factor * 100).round() / 100;
}

double _num(Object? value, [double fallback = 0]) => double.tryParse('${value ?? ''}') ?? fallback;
