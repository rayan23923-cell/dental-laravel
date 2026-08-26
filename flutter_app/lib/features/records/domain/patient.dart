/// Mirrors `App\Http\Resources\PatientResource`. `patients` is
/// staff-only server-side (`permission:patients,*` — a Doctor token 403s
/// every route, see `App\Http\Middleware\EnsureUserHasPermission`), so
/// this whole `records` feature is only ever reached from a staff
/// session's nav.
class Patient {
  const Patient({
    required this.id,
    required this.name,
    required this.phone,
    required this.stageId,
    required this.doctorId,
    required this.stageName,
    required this.doctorName,
  });

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String?,
        stageId: json['stage_id'] as int?,
        doctorId: json['doctor_id'] as int?,
        stageName: (json['stage'] as Map<String, dynamic>?)?['name'] as String?,
        doctorName: (json['doctor'] as Map<String, dynamic>?)?['name'] as String?,
      );

  final int id;
  final String name;
  final String? phone;
  final int? stageId;
  final int? doctorId;
  final String? stageName;
  final String? doctorName;
}
