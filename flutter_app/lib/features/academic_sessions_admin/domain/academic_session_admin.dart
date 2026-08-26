class AcademicSessionAdmin {
  const AcademicSessionAdmin({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.isActive,
    required this.isCurrent,
    required this.groupsCount,
    required this.tasksCount,
  });

  factory AcademicSessionAdmin.fromJson(Map<String, dynamic> json) => AcademicSessionAdmin(
        id: json['id'] as int,
        name: json['name'] as String,
        startDate: _trimDate(json['start_date'] as String?),
        endDate: _trimDate(json['end_date'] as String?),
        isActive: json['is_active'] as bool? ?? true,
        isCurrent: json['is_current'] as bool? ?? false,
        groupsCount: json['groups_count'] as int? ?? 0,
        tasksCount: json['tasks_count'] as int? ?? 0,
      );

  final int id;
  final String name;
  final String startDate;
  final String endDate;
  final bool isActive;
  final bool isCurrent;
  final int groupsCount;
  final int tasksCount;

  static String _trimDate(String? raw) => (raw != null && raw.length >= 10) ? raw.substring(0, 10) : (raw ?? '');
}

/// `Api\AcademicSessionController::show()`'s response shape: `{session,
/// stats}`, not a bare session — distinct from the index-list rows above,
/// which is why this isn't just `AcademicSessionAdmin` with extra nullable
/// fields.
class AcademicSessionStats {
  const AcademicSessionStats({
    required this.doctors,
    required this.groups,
    required this.requiredTasks,
    required this.doneTasks,
    required this.remainingTasks,
  });

  factory AcademicSessionStats.fromJson(Map<String, dynamic> json) => AcademicSessionStats(
        doctors: json['doctors'] as int? ?? 0,
        groups: json['groups'] as int? ?? 0,
        requiredTasks: json['required_tasks'] as int? ?? 0,
        doneTasks: json['done_tasks'] as int? ?? 0,
        remainingTasks: json['remaining_tasks'] as int? ?? 0,
      );

  final int doctors;
  final int groups;
  final int requiredTasks;
  final int doneTasks;
  final int remainingTasks;
}

/// `GET /academic-sessions/current`'s response — just `{id, name}` (or
/// `null` if no academic year is active). Deliberately its own small class
/// rather than reusing [AcademicSessionAdmin] with defaulted-out fields —
/// this is a different, smaller server contract (see
/// `Api\AcademicSessionController::current()`), consumed only for display
/// (the dashboard header, and the Doctors/Groups/Tasks/Task-Progress
/// screens' `AcademicYearBanner`), never for editing.
class CurrentAcademicYear {
  const CurrentAcademicYear({required this.id, required this.name});

  factory CurrentAcademicYear.fromJson(Map<String, dynamic> json) =>
      CurrentAcademicYear(id: json['id'] as int, name: json['name'] as String? ?? '');

  final int id;
  final String name;
}

class AcademicSessionDetail {
  const AcademicSessionDetail({required this.session, required this.stats});

  factory AcademicSessionDetail.fromJson(Map<String, dynamic> json) => AcademicSessionDetail(
        session: AcademicSessionAdmin.fromJson(json['session'] as Map<String, dynamic>),
        stats: AcademicSessionStats.fromJson(json['stats'] as Map<String, dynamic>),
      );

  final AcademicSessionAdmin session;
  final AcademicSessionStats stats;
}
