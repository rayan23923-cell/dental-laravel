/// A task's points setup (`tasks.scoring`), the same JSON the web's
/// `ScoringEditor.vue` edits and `App\Support\TaskScoring::rules()` /
/// `normalize()` accept (2026-10-17, brought to the app from the web).
///
/// Mutable on purpose: like the web editor, the form edits one object in
/// place and sends it back as-is with [toJson].
library;

double? _num(Object? v) => v == null || v == '' ? null : double.tryParse(v.toString());

/// Prints a number the way the web shows it: `10` not `10.0`, at most 2 decimals.
String fmtPoints(num? v) {
  if (v == null) return '';
  final rounded = (v * 100).round() / 100;
  return rounded == rounded.roundToDouble() ? rounded.toInt().toString() : rounded.toString();
}

double roundPoints(double v) => (v * 100).round() / 100;

class ScoringOption {
  ScoringOption({this.label = '', this.points = 0, this.enabled = true});

  factory ScoringOption.fromJson(Map<String, dynamic> json) => ScoringOption(
        label: json['label']?.toString() ?? '',
        points: _num(json['points']) ?? 0,
        enabled: json['enabled'] as bool? ?? true,
      );

  String label;
  double points;
  bool enabled;

  Map<String, dynamic> toJson() => {'label': label, 'points': points, 'enabled': enabled};
}

class ScoringModifier {
  ScoringModifier({this.label = '', this.factor = 1});

  factory ScoringModifier.fromJson(Map<String, dynamic> json) =>
      ScoringModifier(label: json['label']?.toString() ?? '', factor: _num(json['factor']) ?? 1);

  String label;
  double factor;

  Map<String, dynamic> toJson() => {'label': label, 'factor': factor};
}

/// A case-sheet step graded on the sheet (prosthodontics), or one added by
/// hand ([custom]), graded on the task's points panel.
class ScoringStep {
  ScoringStep({required this.key, this.label = '', this.max = 10, this.enabled = true, this.custom = false});

  factory ScoringStep.fromJson(Map<String, dynamic> json) => ScoringStep(
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        max: _num(json['max']) ?? 0,
        enabled: json['enabled'] as bool? ?? true,
        custom: json['custom'] as bool? ?? false,
      );

  String key;
  String label;
  double max;
  bool enabled;
  bool custom;

  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'max': max, 'enabled': enabled, 'custom': custom};
}

/// A part that must be ticked to complete a case, optionally graded up to [max].
class ScoringCheck {
  ScoringCheck({this.label = '', this.scored = false, this.max});

  factory ScoringCheck.fromJson(Map<String, dynamic> json) => ScoringCheck(
        label: json['label']?.toString() ?? '',
        scored: json['scored'] as bool? ?? false,
        max: _num(json['max']),
      );

  String label;
  bool scored;
  double? max;

  Map<String, dynamic> toJson() => {'label': label, if (scored) 'scored': true, if (scored) 'max': max};
}

class TaskScoringSetup {
  TaskScoringSetup({
    this.measure = 'count',
    this.minPoints,
    this.weight,
    List<ScoringOption>? options,
    List<ScoringModifier>? modifiers,
    List<ScoringStep>? steps,
    this.graded = false,
    List<ScoringCheck>? checklist,
    this.endo = false,
    this.pointsOff = false,
  })  : options = options ?? [],
        modifiers = modifiers ?? [],
        steps = steps ?? [],
        checklist = checklist ?? [];

  factory TaskScoringSetup.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
        (json[key] as List<dynamic>? ?? const []).map((e) => f(e as Map<String, dynamic>)).toList();
    return TaskScoringSetup(
      measure: json['measure'] as String? ?? 'count',
      minPoints: _num(json['min_points']),
      weight: _num(json['weight']),
      options: list('options', ScoringOption.fromJson),
      modifiers: list('modifiers', ScoringModifier.fromJson),
      steps: list('steps', ScoringStep.fromJson),
      graded: json['graded'] as bool? ?? false,
      checklist: list('checklist', ScoringCheck.fromJson),
      endo: json['endo'] as bool? ?? false,
      pointsOff: json['points_off'] as bool? ?? false,
    );
  }

  static TaskScoringSetup? maybe(Object? json) =>
      json is Map<String, dynamic> ? TaskScoringSetup.fromJson(json) : null;

  /// 'count' | 'points' | 'both'
  String measure;
  double? minPoints;
  double? weight;
  final List<ScoringOption> options;
  final List<ScoringModifier> modifiers;
  final List<ScoringStep> steps;
  bool graded;
  final List<ScoringCheck> checklist;
  bool endo;

  /// Points switched off (2026-10-16): the lists stay, their points and totals are hidden.
  bool pointsOff;

  /// Whether the task has work to record on a case (web `hasWork()`).
  bool get hasWork => options.isNotEmpty || checklist.isNotEmpty;

  /// Whether anything besides the points is set up (web Edit.vue `hasLists()`).
  bool get hasLists => options.isNotEmpty || checklist.isNotEmpty || steps.isNotEmpty || endo;

  double get optionsTotal => roundPoints(options.where((o) => o.enabled).fold(0.0, (s, o) => s + o.points));
  double get stepsTotal => roundPoints(steps.where((s) => s.enabled).fold(0.0, (s, st) => s + st.max));
  double get checklistTotal => roundPoints(checklist.where((c) => c.scored).fold(0.0, (s, c) => s + (c.max ?? 0)));

  Map<String, dynamic> toJson() => {
        'measure': measure,
        'min_points': minPoints,
        'weight': weight,
        'options': [for (final o in options) o.toJson()],
        'modifiers': [for (final m in modifiers) m.toJson()],
        'steps': [for (final s in steps) s.toJson()],
        'graded': graded,
        'checklist': [for (final c in checklist) c.toJson()],
        'endo': endo,
        'points_off': pointsOff,
      };
}

/// One row of a case-sheet type's requirements table (web Tasks/Create.vue):
/// every enabled row is saved as its own task.
class ScoringTemplateRow {
  ScoringTemplateRow({
    required this.enabled,
    this.stage,
    required this.title,
    required this.requiredCount,
    this.caseSheetTypeId,
    this.scoring,
    this.off = false,
  }) : baseEnabled = enabled;

  factory ScoringTemplateRow.fromJson(Map<String, dynamic> json) => ScoringTemplateRow(
        enabled: json['enabled'] as bool? ?? true,
        stage: json['stage'] as int?,
        title: json['title']?.toString() ?? '',
        requiredCount: (json['required_count'] as num?)?.toInt() ?? 1,
        caseSheetTypeId: json['case_sheet_type_id'] as int?,
        scoring: TaskScoringSetup.maybe(json['scoring']),
        off: json['off'] as bool? ?? false,
      );

  bool enabled;

  /// 4 or 5 when the row belongs to one stage only.
  final int? stage;
  String title;
  int requiredCount;
  int? caseSheetTypeId;
  TaskScoringSetup? scoring;

  /// Kept in the table switched off (an older row a department may still use).
  final bool off;

  /// The template's own on/off, before the stage rule switched it.
  final bool baseEnabled;

  bool get pointsOn => scoring != null && !scoring!.pointsOff;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'stage': stage,
        'title': title,
        'required_count': requiredCount,
        'case_sheet_type_id': caseSheetTypeId,
        'scoring': scoring?.toJson(),
      };
}

/// A case-sheet type's table (`GET /tasks/scoring-templates`, keyed by type id).
class ScoringTemplate {
  const ScoringTemplate({required this.passPercent, required this.rows});

  factory ScoringTemplate.fromJson(Map<String, dynamic> json) => ScoringTemplate(
        passPercent: _num(json['pass_percent']),
        rows: (json['rows'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>(),
      );

  final double? passPercent;

  /// Raw rows, parsed afresh each time the type is picked so edits never leak back.
  final List<Map<String, dynamic>> rows;

  List<ScoringTemplateRow> freshRows() => rows.map(ScoringTemplateRow.fromJson).toList();
}

/// A doctor's result on a department (`TaskScoring::doctorResult()`), shown
/// like the web's `ScoreSummary.vue`.
class DepartmentScore {
  const DepartmentScore({required this.percent, required this.passPercent, required this.passed, required this.tasks});

  factory DepartmentScore.fromJson(Map<String, dynamic> json) => DepartmentScore(
        percent: _num(json['percent']) ?? 0,
        passPercent: _num(json['pass_percent']) ?? 100,
        passed: json['passed'] as bool? ?? false,
        tasks: (json['tasks'] as List<dynamic>? ?? const [])
            .map((e) => DepartmentScoreRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static DepartmentScore? maybe(Object? json) => json is Map<String, dynamic> ? DepartmentScore.fromJson(json) : null;

  final double percent;
  final double passPercent;
  final bool passed;
  final List<DepartmentScoreRow> tasks;
}

class DepartmentScoreRow {
  const DepartmentScoreRow({
    required this.taskId,
    required this.title,
    required this.cases,
    required this.requiredCount,
    required this.points,
    this.minPoints,
    this.weight,
    required this.percent,
  });

  factory DepartmentScoreRow.fromJson(Map<String, dynamic> json) => DepartmentScoreRow(
        taskId: json['task_id'] as int,
        title: json['title']?.toString() ?? '',
        cases: (json['cases'] as num?)?.toInt() ?? 0,
        requiredCount: (json['required_count'] as num?)?.toInt() ?? 0,
        points: _num(json['points']) ?? 0,
        minPoints: _num(json['min_points']),
        weight: _num(json['weight']),
        percent: _num(json['percent']) ?? 0,
      );

  final int taskId;
  final String title;
  final int cases;
  final int requiredCount;
  final double points;
  final double? minPoints;
  final double? weight;
  final double percent;
}
