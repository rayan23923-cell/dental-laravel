/// One weekly recurring time slot a group meets in. `day` is one of the 5
/// exact Arabic weekday strings the original app stores
/// (`resources/js/Pages/Groups/Index.vue`'s own `DAYS` constant — Sunday
/// through Thursday, the regional work week) — not translated or
/// reformatted, since the column stores this string verbatim and other
/// screens (e.g. a doctor's schedule) compare against it directly.
class GroupSlot {
  const GroupSlot({required this.day, required this.startTime, required this.endTime});

  factory GroupSlot.fromJson(Map<String, dynamic> json) => GroupSlot(
        day: json['day'] as String? ?? kGroupDays.first,
        startTime: _trimTime(json['start_time'] as String?),
        endTime: _trimTime(json['end_time'] as String?),
      );

  final String day;
  final String startTime;
  final String endTime;

  Map<String, dynamic> toJson() => {'day': day, 'start_time': startTime, 'end_time': endTime};

  GroupSlot copyWith({String? day, String? startTime, String? endTime}) => GroupSlot(
        day: day ?? this.day,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
      );

  static String _trimTime(String? raw) => (raw != null && raw.length >= 5) ? raw.substring(0, 5) : (raw ?? '');
}

const kGroupDays = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس'];

/// A doctor already enrolled in a group — the
/// `doctors:id,name,email,username` column-select `GroupController::show()`
/// returns (`username` added alongside the group roster PDF, which lists it
/// as a column).
class GroupMember {
  const GroupMember({required this.id, required this.name, required this.email, required this.username});

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        username: json['username'] as String? ?? '',
      );

  final int id;
  final String name;
  final String email;
  final String username;
}

/// Mirrors the plain (non-Resource-wrapped) JSON `Api\GroupController`
/// returns — `index()`'s own shape for the list, `show()`'s fuller shape
/// (adds `doctors`) for the detail screen. `members`/`slots` are empty
/// when parsed from an `index()` row that didn't include them (`slots` is
/// included there; `doctors` isn't — only `doctorsCount` is).
class GroupAdmin {
  const GroupAdmin({
    required this.id,
    required this.name,
    required this.stageId,
    required this.stageName,
    required this.academicSessionId,
    required this.doctorsCount,
    required this.slots,
    required this.members,
  });

  factory GroupAdmin.fromJson(Map<String, dynamic> json) {
    final stage = json['stage'] as Map<String, dynamic>?;
    return GroupAdmin(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      stageId: json['stage_id'] as int? ?? stage?['id'] as int?,
      stageName: stage?['name'] as String?,
      academicSessionId: json['academic_session_id'] as int?,
      doctorsCount: json['doctors_count'] as int? ?? (json['doctors'] as List<dynamic>?)?.length ?? 0,
      slots: (json['slots'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().map(GroupSlot.fromJson).toList(),
      members:
          (json['doctors'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().map(GroupMember.fromJson).toList(),
    );
  }

  final int id;
  final String name;
  final int? stageId;
  final String? stageName;
  final int? academicSessionId;
  final int doctorsCount;
  final List<GroupSlot> slots;
  final List<GroupMember> members;
}

/// One row from `GET /groups-available-doctors` — a doctor not yet
/// enrolled in any group for the given academic session, per
/// `GroupController::availableDoctors()`'s own doc comment on what
/// "available" means.
class AvailableDoctor {
  const AvailableDoctor({required this.id, required this.name});

  factory AvailableDoctor.fromJson(Map<String, dynamic> json) =>
      AvailableDoctor(id: json['id'] as int, name: json['name'] as String? ?? '');

  final int id;
  final String name;
}
