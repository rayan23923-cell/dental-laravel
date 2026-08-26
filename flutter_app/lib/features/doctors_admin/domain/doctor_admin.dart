/// Mirrors `App\Http\Resources\DoctorResource` — the admin-facing `Doctor`
/// record (name/username/email/education/stage), distinct from
/// `DoctorAccount` (the authenticated-session shape from `/doctor/login`
/// and `/me`). `doctors` is staff-only server-side
/// (`permission:doctors,*`), same as `patients` — see
/// `EnsureUserHasPermission`.
class DoctorAdmin {
  const DoctorAdmin({
    required this.id,
    required this.name,
    required this.username,
    required this.email,
    required this.phone,
    required this.profileImageUrl,
    required this.educationTypeId,
    required this.stageId,
    required this.educationTypeName,
    required this.stageName,
    required this.academicSessionId,
    required this.academicSessionName,
    required this.nfcTagId,
    required this.groupNames,
  });

  factory DoctorAdmin.fromJson(Map<String, dynamic> json) {
    final educationType = json['education_type'] as Map<String, dynamic>?;
    final stage = json['stage'] as Map<String, dynamic>?;
    final academicSession = json['academic_session'] as Map<String, dynamic>?;
    final groups = json['groups'] as List<dynamic>?;

    return DoctorAdmin(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      educationTypeId: json['education_type_id'] as int?,
      stageId: json['stage_id'] as int?,
      educationTypeName: educationType?['name'] as String?,
      stageName: stage?['name'] as String?,
      academicSessionId: json['academic_session_id'] as int?,
      academicSessionName: academicSession?['name'] as String?,
      nfcTagId: json['nfc_tag_id'] as String?,
      groupNames: groups == null
          ? const []
          : [for (final g in groups) (g as Map<String, dynamic>)['name'] as String? ?? ''],
    );
  }

  final int id;
  final String name;
  final String username;
  final String email;
  final String? phone;
  final String? profileImageUrl;
  final int? educationTypeId;
  final int? stageId;
  final String? educationTypeName;
  final String? stageName;
  final int? academicSessionId;
  final String? academicSessionName;
  final String? nfcTagId;
  // Only present when the list response eager-loaded `groups` (the doctors
  // list does; `/doctors/{id}` doesn't) — used by the roster PDF.
  final List<String> groupNames;
}
