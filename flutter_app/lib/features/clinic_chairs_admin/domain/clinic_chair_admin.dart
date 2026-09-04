/// Domain models for the clinic seating map (2026-09-04, by request —
/// "اضفها الى فلتر", porting the web-only `ClinicChairs/Index.vue` feature
/// to Flutter). Mirrors `Api\ClinicChairController`'s plain
/// (non-Resource-wrapped) JSON exactly, matching `GroupAdmin`'s own
/// convention in `group_admin.dart`.
library;

/// A doctor as listed inside a `ChairGroup`'s own roster — just enough to
/// render the group-membership list, not the full `ChairDoctor` shape a
/// chair's own `doctor` relation carries (which also has a photo).
class ChairGroupDoctor {
  const ChairGroupDoctor({required this.id, required this.name});

  factory ChairGroupDoctor.fromJson(Map<String, dynamic> json) =>
      ChairGroupDoctor(id: json['id'] as int, name: json['name'] as String? ?? '');

  final int id;
  final String name;
}

class ChairGroup {
  const ChairGroup({required this.id, required this.name, required this.stageId, required this.stageName, required this.doctors});

  factory ChairGroup.fromJson(Map<String, dynamic> json) {
    final stage = json['stage'] as Map<String, dynamic>?;
    return ChairGroup(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      stageId: json['stage_id'] as int? ?? stage?['id'] as int?,
      stageName: stage?['name'] as String?,
      doctors: (json['doctors'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ChairGroupDoctor.fromJson)
          .toList(),
    );
  }

  final int id;
  final String name;
  final int? stageId;
  final String? stageName;
  final List<ChairGroupDoctor> doctors;
}

/// A chair's own assigned doctor — `profileImageUrl` is a full URL
/// (`Api\ClinicChairController::withPhotoUrl()` converts the raw
/// storage-disk path server-side, same `DoctorResource` convention
/// `doctor_admin.dart`'s own `profileImageUrl` already relies on).
class ChairDoctor {
  const ChairDoctor({required this.id, required this.name, required this.profileImageUrl});

  factory ChairDoctor.fromJson(Map<String, dynamic> json) => ChairDoctor(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        profileImageUrl: json['profile_image_url'] as String?,
      );

  final int id;
  final String name;
  final String? profileImageUrl;
}

class ChairStage {
  const ChairStage({required this.id, required this.name});

  factory ChairStage.fromJson(Map<String, dynamic> json) =>
      ChairStage(id: json['id'] as int, name: json['name'] as String? ?? '');

  final int id;
  final String name;
}

/// One physical chair position — `group`/`doctor` are both null for an
/// empty chair, `group` only for the plain group-level assignment mode,
/// both together for the individual-doctor mode (see
/// `ClinicChair`'s own PHP doc comment for why both are kept).
class ClinicChairAdmin {
  const ClinicChairAdmin({
    required this.id,
    required this.rowNumber,
    required this.columnNumber,
    required this.label,
    required this.group,
    required this.doctor,
  });

  factory ClinicChairAdmin.fromJson(Map<String, dynamic> json) => ClinicChairAdmin(
        id: json['id'] as int,
        rowNumber: json['row_number'] as int,
        columnNumber: json['column_number'] as int,
        label: json['label'] as String?,
        group: json['group'] != null ? ChairGroup.fromJson(json['group'] as Map<String, dynamic>) : null,
        doctor: json['doctor'] != null ? ChairDoctor.fromJson(json['doctor'] as Map<String, dynamic>) : null,
      );

  final int id;
  final int rowNumber;
  final int columnNumber;
  final String? label;
  final ChairGroup? group;
  final ChairDoctor? doctor;

  String get positionLabel => label ?? '$rowNumber-$columnNumber';
}

/// The whole `GET /clinic-chairs` payload — chairs plus everything the
/// sidebar needs (assignable groups, stage filter options, which doctors
/// already have a chair somewhere).
class ClinicChairsBoard {
  const ClinicChairsBoard({
    required this.chairs,
    required this.groups,
    required this.stages,
    required this.assignedDoctorIds,
    required this.currentSessionName,
  });

  factory ClinicChairsBoard.fromJson(Map<String, dynamic> json) {
    final session = json['current_session'] as Map<String, dynamic>?;
    return ClinicChairsBoard(
      chairs: (json['chairs'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ClinicChairAdmin.fromJson)
          .toList(),
      groups: (json['groups'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().map(ChairGroup.fromJson).toList(),
      stages: (json['stages'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().map(ChairStage.fromJson).toList(),
      assignedDoctorIds: (json['assigned_doctor_ids'] as List<dynamic>? ?? []).map((e) => e as int).toSet(),
      currentSessionName: session?['name'] as String?,
    );
  }

  final List<ClinicChairAdmin> chairs;
  final List<ChairGroup> groups;
  final List<ChairStage> stages;
  final Set<int> assignedDoctorIds;
  final String? currentSessionName;

  /// How many of [group]'s doctors don't have a chair anywhere yet —
  /// drives the "Distribute" (all unseated) vs "Update (N new)" (some
  /// already seated) button label, same logic as the web's own
  /// `unseatedCount()`.
  int unseatedCount(ChairGroup group) => group.doctors.where((d) => !assignedDoctorIds.contains(d.id)).length;

  /// Rows sorted and grouped, columns sorted within each — same shape the
  /// web's own `rows` computed builds.
  List<({int rowNumber, List<ClinicChairAdmin> chairs})> get rows {
    final byRow = <int, List<ClinicChairAdmin>>{};
    for (final chair in chairs) {
      (byRow[chair.rowNumber] ??= []).add(chair);
    }
    final rowNumbers = byRow.keys.toList()..sort();
    return [
      for (final rowNumber in rowNumbers)
        (rowNumber: rowNumber, chairs: byRow[rowNumber]!..sort((a, b) => a.columnNumber.compareTo(b.columnNumber))),
    ];
  }
}
