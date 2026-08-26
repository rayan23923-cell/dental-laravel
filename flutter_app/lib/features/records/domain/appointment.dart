/// Mirrors `App\Http\Resources\AppointmentResource`. `doctor_id` here
/// references `users.id` (staff), not `doctors.id` — a confirmed FK
/// oddity in the source schema (see `App\Models\Appointment`'s own doc
/// comment), unrelated to the `Doctor`/`DoctorAccount` used everywhere
/// else in this app. The mobile form never shows it as a picker: it's
/// silently filled with the logged-in staff user's own id, same precedent
/// as case-sheet creation's `doctor_id` auto-fill.
class Appointment {
  const Appointment({
    required this.id,
    required this.fullName,
    required this.patientId,
    required this.patientRegistrationId,
    required this.doctorId,
    required this.taskId,
    required this.appointmentDate,
    required this.confirmedByAccountant,
    required this.pinned,
    required this.patientName,
    required this.patientRegistrationName,
    required this.patientRegistrationPhone,
    required this.staffName,
    required this.taskTitle,
    required this.paidTotal,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) {
    final registration = json['patient_registration'] as Map<String, dynamic>?;
    return Appointment(
      id: json['id'] as int,
      fullName: json['full_name'] as String? ?? '',
      patientId: json['patient_id'] as int?,
      patientRegistrationId: json['patient_registration_id'] as int?,
      doctorId: json['doctor_id'] as int?,
      taskId: json['task_id'] as int?,
      appointmentDate: json['appointment_date'] as String?,
      confirmedByAccountant: json['confirmed_by_accountant'] as bool? ?? false,
      pinned: json['pinned'] as bool? ?? false,
      patientName: (json['patient'] as Map<String, dynamic>?)?['name'] as String?,
      patientRegistrationName: registration?['name'] as String?,
      patientRegistrationPhone: registration?['phone'] as String?,
      staffName: (json['doctor'] as Map<String, dynamic>?)?['full_name'] as String?,
      taskTitle: (json['task'] as Map<String, dynamic>?)?['title'] as String?,
      paidTotal: (json['paid_total'] as num?)?.toDouble(),
    );
  }

  final int id;
  final String fullName;
  final int? patientId;
  final int? patientRegistrationId;
  final int? doctorId;
  final int? taskId;
  final String? appointmentDate;
  final bool confirmedByAccountant;
  final bool pinned;
  final String? patientName;
  final String? patientRegistrationName;
  final String? patientRegistrationPhone;
  final String? staffName;
  final String? taskTitle;
  final double? paidTotal;

  /// The person to show regardless of which link this appointment used —
  /// same precedent as `Payment.personName` from Phase 1.
  String get personName => patientRegistrationName ?? patientName ?? fullName;
}
