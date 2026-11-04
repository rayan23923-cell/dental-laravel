import 'discount_breakdown.dart';

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
    this.patientCode,
    required this.age,
    required this.sex,
    required this.address,
    required this.occupation,
    required this.serviceId,
    required this.registerDayId,
    required this.serviceName,
    this.servicePrice,
    this.discountEligible = false,
    this.discountType,
    this.discountStage,
    this.discountWorkplace,
    this.discountLine,
    this.discount,
    this.supported = false,
    this.supportCode,
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
    this.labSamplePrintedAt,
    this.labResultReceivedAt,
    this.screeningDiagnoses = const [],
    this.screeningDiagnosisText,
    this.caseLink,
    this.linkAttemptsCount = 0,
    this.suspiciousAttemptsCount = 0,
  });

  factory PatientRegistration.fromJson(Map<String, dynamic> json) {
    final service = json['service'] as Map<String, dynamic>?;
    final day = json['register_day'] as Map<String, dynamic>?;
    final task = json['task'] as Map<String, dynamic>?;
    return PatientRegistration(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      patientCode: json['patient_code'] as String?,
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
      discountType: json['discount_type'] as String?,
      discountStage: json['discount_stage'] as String?,
      discountWorkplace: json['discount_workplace'] as String?,
      discountLine: json['discount_line'] as String?,
      discount: DiscountBreakdown.fromJson(json['discount']),
      supported: json['supported'] == true,
      supportCode: json['support_code'] as String?,
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
      labSamplePrintedAt: json['lab_sample_printed_at'] as String?,
      labResultReceivedAt: json['lab_result_received_at'] as String?,
      screeningDiagnoses: ((json['screening_diagnoses'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
      screeningDiagnosisText: json['screening_diagnosis_text'] as String?,
      caseLink: RegistrationCaseLink.fromJson(json['case_link']),
      linkAttemptsCount: (json['link_attempts_count'] as num?)?.toInt() ?? 0,
      suspiciousAttemptsCount: (json['suspicious_attempts_count'] as num?)?.toInt() ?? 0,
    );
  }

  final int id;
  final String name;

  /// Free with a care card (2026-11-01): no service or lab fee.
  final bool supported;
  final String? supportCode;
  final String phone;

  /// The 6-digit code printed under the ticket QR (2026-11-04), typed by
  /// the doctor to link the patient when the camera can't be used.
  final String? patientCode;
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

  /// 'student' or 'employee' when eligible, with the optional stage or
  /// workplace (2026-10-25).
  final String? discountType;
  final String? discountStage;
  final String? discountWorkplace;

  /// What the ticket prints about the discount, e.g. "طالب · المرحلة
  /// الرابعة — خصم 50% من 20,000"; null when not eligible.
  final String? discountLine;

  /// The same as separate amounts for the ticket's rows (2026-10-25).
  final DiscountBreakdown? discount;
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

  /// Waiting screen (2026-11-02): when the samples sheet was printed, and
  /// when the patient collected the result ("تم استلام النتيجة").
  final String? labSamplePrintedAt;
  final String? labResultReceivedAt;

  /// "غير سليم" diagnosis (2026-11-03, by request): codes 'B' / 'C' /
  /// 'HIV' and the printed text, e.g. "التهاب الكبد B، HIV".
  final List<String> screeningDiagnoses;
  final String? screeningDiagnosisText;

  /// The case sheet this patient was linked to, and refused attempts to
  /// link it, e.g. another doctor entering the same receipt (2026-11-04,
  /// by request, against stolen or forged receipts). Only the registry
  /// list sends these.
  final RegistrationCaseLink? caseLink;
  final int linkAttemptsCount;
  final int suspiciousAttemptsCount;

  bool get isLabResultReceived => labResultReceivedAt != null;

  bool get isScreeningClear => screeningStatus == 'clear';
  bool get isScreened => screeningStatus != 'pending';
}

/// Who a patient was linked to: doctor, task (e.g. قلع) and department.
class RegistrationCaseLink {
  const RegistrationCaseLink({this.doctor, this.task, this.department, this.method, this.started = false, this.linkedAt});

  static RegistrationCaseLink? fromJson(Object? json) {
    if (json is! Map) return null;
    return RegistrationCaseLink(
      doctor: json['doctor'] as String?,
      task: json['task'] as String?,
      department: json['department'] as String?,
      method: json['method'] as String?,
      started: json['started'] == true,
      linkedAt: json['linked_at'] as String?,
    );
  }

  final String? doctor;
  final String? task;
  final String? department;
  final String? method;
  final bool started;
  final String? linkedAt;

  String get label => [task, doctor].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
}

/// An earlier patient matching the name or phone typed on the
/// registration form (2026-11-04, by request): `PreviousPatients::suggest()`.
class PreviousPatient {
  const PreviousPatient({
    required this.name,
    this.phone,
    this.visits = 1,
    this.lastVisit,
    this.exactName = false,
    this.exactPhone = false,
  });

  factory PreviousPatient.fromJson(Map<String, dynamic> json) => PreviousPatient(
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String?,
        visits: (json['visits'] as num?)?.toInt() ?? 1,
        lastVisit: json['last_visit'] as String?,
        exactName: json['exact_name'] == true,
        exactPhone: json['exact_phone'] == true,
      );

  final String name;
  final String? phone;
  final int visits;
  final String? lastVisit;
  final bool exactName;
  final bool exactPhone;
}
