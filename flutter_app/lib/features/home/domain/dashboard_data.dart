/// Mirrors the props of the web `Dashboard.vue`, as `GET /dashboard`
/// returns them (`DashboardController::dashboardData()`).
class DashboardData {
  const DashboardData({
    required this.doctors,
    required this.registrations,
    required this.registrationsToday,
    required this.tasks,
    required this.tasksDone,
    required this.tasksNotDone,
    required this.instancesCompleted,
    required this.instancesAssigned,
    required this.instancesPending,
    required this.latestDoctors,
    required this.todayIncome,
    required this.monthIncome,
    required this.currency,
    required this.educationTypes,
    required this.canDoctors,
    required this.canTaskProgress,
    required this.canPayments,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? const {};
    final income = json['income'] as Map<String, dynamic>?;
    final can = json['can'] as Map<String, dynamic>? ?? const {};
    int n(String key) => (stats[key] as num?)?.toInt() ?? 0;
    double? total(String period) =>
        double.tryParse((income?[period] as Map<String, dynamic>?)?['total']?.toString() ?? '');

    return DashboardData(
      doctors: n('doctors'),
      registrations: n('registrations'),
      registrationsToday: n('registrations_today'),
      tasks: n('tasks'),
      tasksDone: n('tasks_done'),
      tasksNotDone: n('tasks_not_done'),
      instancesCompleted: n('instances_completed'),
      instancesAssigned: n('instances_assigned'),
      instancesPending: n('instances_pending'),
      latestDoctors: [
        for (final d in json['latestDoctors'] as List<dynamic>? ?? const [])
          DashboardDoctor.fromJson(d as Map<String, dynamic>),
      ],
      todayIncome: income == null ? null : total('today') ?? 0,
      monthIncome: income == null ? null : total('month') ?? 0,
      currency: json['currency'] as String? ?? '',
      educationTypes: [
        for (final e in json['educationTypes'] as List<dynamic>? ?? const [])
          (id: (e as Map<String, dynamic>)['id'] as int, name: e['name'] as String? ?? ''),
      ],
      canDoctors: can['doctors'] == true,
      canTaskProgress: can['task_progress'] == true,
      canPayments: can['payments'] == true,
    );
  }

  final int doctors;
  final int registrations;
  final int registrationsToday;
  final int tasks;
  final int tasksDone;
  final int tasksNotDone;
  final int instancesCompleted;
  final int instancesAssigned;
  final int instancesPending;
  final List<DashboardDoctor> latestDoctors;

  /// Null when the user's role can't open payments (no income tile then).
  final double? todayIncome;
  final double? monthIncome;
  final String currency;
  final List<({int id, String name})> educationTypes;
  final bool canDoctors;
  final bool canTaskProgress;
  final bool canPayments;

  /// Done tasks as a whole percentage, as the web's `donePct`.
  int get donePercent {
    final all = tasksDone + tasksNotDone;
    return all > 0 ? (tasksDone * 100 / all).round() : 0;
  }

  int get instancesTotal => instancesCompleted + instancesAssigned + instancesPending;
}

class DashboardDoctor {
  const DashboardDoctor({required this.id, required this.name, this.educationType, this.createdAt});

  factory DashboardDoctor.fromJson(Map<String, dynamic> json) => DashboardDoctor(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        educationType: json['education_type'] as String?,
        createdAt: json['created_at'] as String?,
      );

  final int id;
  final String name;
  final String? educationType;
  final String? createdAt;
}

/// One department/stage row of "المهام المطلوبة لكل قسم ومرحلة".
class DashboardDepartment {
  const DashboardDepartment({
    required this.department,
    required this.stage,
    required this.required,
    required this.completed,
    required this.tasks,
  });

  factory DashboardDepartment.fromJson(Map<String, dynamic> json) => DashboardDepartment(
        department: json['department'] as String? ?? '',
        stage: json['stage'] as String?,
        required: (json['required'] as num?)?.toInt() ?? 0,
        completed: (json['completed'] as num?)?.toInt() ?? 0,
        tasks: [
          for (final t in json['tasks'] as List<dynamic>? ?? const [])
            (
              id: (t as Map<String, dynamic>)['id'] as int,
              title: t['title'] as String? ?? '',
              required: (t['required'] as num?)?.toInt() ?? 0,
              completed: (t['completed'] as num?)?.toInt() ?? 0,
              remaining: (t['remaining'] as num?)?.toInt() ?? 0,
            ),
        ],
      );

  final String department;
  final String? stage;
  final int required;
  final int completed;
  final List<({int id, String title, int required, int completed, int remaining})> tasks;
}

/// The app's per-role home panels (`GET /dashboard/desk`, 2026-10-18):
/// each one present only when the user may open it.
class DeskPanels {
  const DeskPanels({this.registrations, this.lab, this.payments});

  factory DeskPanels.fromJson(Map<String, dynamic> json) {
    final panels = json['panels'] as Map<String, dynamic>? ?? const {};
    int n(Map<String, dynamic>? m, String key) => (m?[key] as num?)?.toInt() ?? 0;
    final reg = panels['registrations'] as Map<String, dynamic>?;
    final lab = panels['lab'] as Map<String, dynamic>?;
    final pay = panels['payments'] as Map<String, dynamic>?;
    final periods = pay?['periods'] as Map<String, dynamic>? ?? const {};
    ({double total, int count}) period(String key) {
      final p = periods[key] as Map<String, dynamic>?;
      return (total: double.tryParse(p?['total']?.toString() ?? '') ?? 0, count: n(p, 'count'));
    }

    return DeskPanels(
      registrations: reg == null ? null : (today: n(reg, 'today'), total: n(reg, 'total')),
      lab: lab == null
          ? null
          : (pending: n(lab, 'pending'), clear: n(lab, 'clear'), flagged: n(lab, 'flagged'), checkedToday: n(lab, 'checked_today')),
      payments: pay == null
          ? null
          : (
              today: period('today'),
              week: period('week'),
              month: period('month'),
              currency: pay['currency'] as String? ?? '',
            ),
    );
  }

  final ({int today, int total})? registrations;
  final ({int pending, int clear, int flagged, int checkedToday})? lab;
  final ({
    ({double total, int count}) today,
    ({double total, int count}) week,
    ({double total, int count}) month,
    String currency,
  })? payments;
}
