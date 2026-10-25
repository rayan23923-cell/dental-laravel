/// Mirrors `App\Http\Resources\PatientRegistrationResource` — the
/// reception-desk "register a new patient with a service + day" record
/// (table `patients_simple`). Deliberately separate from
/// `features/records/domain/patient.dart` (the other, unrelated `patients`
/// table/concept) — see `App\Models\PatientRegistration`'s docblock.
class PatientRegistration {
  const PatientRegistration({
    required this.id,
    required this.name,
    required this.phone,
    required this.age,
    required this.sex,
    required this.address,
    required this.occupation,
    required this.serviceId,
    required this.registerDayId,
    required this.serviceName,
    this.servicePrice,
    this.discountEligible = false,
    required this.registerDayName,
    required this.createdAt,
    required this.taskId,
    required this.taskTitle,
    required this.stageName,
    required this.educationTypeName,
    required this.screeningStatus,
    this.screeningCheckedAt,
    this.screeningCheckedByName,
    this.screeningReusedFrom,
    this.screeningReusedFromCheckedAt,
  });

  factory PatientRegistration.fromJson(Map<String, dynamic> json) {
    final service = json['service'] as Map<String, dynamic>?;
    final day = json['register_day'] as Map<String, dynamic>?;
    final task = json['task'] as Map<String, dynamic>?;
    return PatientRegistration(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      // Added 2026-08-28 for case-sheet QR-autofill — reception already
      // captures these at registration time (`patients_simple.age/sex/
      // address/occupation`); see App\Support\CaseSheetPatientFieldMap.
      age: json['age'] as int?,
      sex: json['sex'] as String?,
      address: json['address'] as String?,
      occupation: json['occupation'] as String?,
      serviceId: json['service_id'] as int?,
      registerDayId: json['register_day_id'] as int?,
      serviceName: service?['name'] as String?,
      // A decimal column, so it may arrive as a string ("25000.00").
      // `service_fee` (2026-10-25) is the price less the student discount
      // when the patient is eligible; older servers only send the price.
      servicePrice: json['service_fee'] != null
          ? double.tryParse(json['service_fee'].toString())
          : service?['price'] == null
              ? null
              : double.tryParse(service!['price'].toString()),
      discountEligible: json['discount_eligible'] == true,
      registerDayName: day?['name'] as String?,
      createdAt: json['created_at'] as String?,
      taskId: json['task_id'] as int?,
      taskTitle: task?['title'] as String?,
      stageName: task?['stage_name'] as String?,
      educationTypeName: task?['education_type_name'] as String?,
      // 'pending' | 'clear' | 'flagged' — see `PatientScreeningGate` on
      // the backend. Defaults to 'pending' for any older cached response
      // shape that predates this field.
      screeningStatus: json['screening_status'] as String? ?? 'pending',
      screeningCheckedAt: json['screening_checked_at'] as String?,
      screeningCheckedByName: (json['screening_checked_by'] as Map<String, dynamic>?)?['full_name'] as String?,
      screeningReusedFrom: json['screening_reused_from'] as int?,
      screeningReusedFromCheckedAt: json['screening_reused_from_checked_at'] as String?,
    );
  }

  final int id;
  final String name;
  final String phone;
  final int? age;
  final String? sex;
  final String? address;
  final String? occupation;
  final int? serviceId;
  final int? registerDayId;
  final String? serviceName;

  /// What registration charges for the service (2026-10-12): its price,
  /// less the student discount when [discountEligible] (2026-10-25);
  /// printed on the ticket as the amount paid.
  final double? servicePrice;

  /// Registered as eligible for the student discount (2026-10-25).
  final bool discountEligible;
  final String? registerDayName;
  final String? createdAt;
  final int? taskId;
  final String? taskTitle;
  final String? stageName;
  final String? educationTypeName;
  final String screeningStatus;

  /// Who recorded the lab result and when (2026-10-17) — sent only by
  /// the QR/state responses, which load the checker; null elsewhere.
  final String? screeningCheckedAt;
  final String? screeningCheckedByName;

  /// The earlier registration whose clear result this one reused, and
  /// that earlier test's date.
  final int? screeningReusedFrom;
  final String? screeningReusedFromCheckedAt;

  bool get isScreeningClear => screeningStatus == 'clear';
  bool get isScreened => screeningStatus != 'pending';
}
