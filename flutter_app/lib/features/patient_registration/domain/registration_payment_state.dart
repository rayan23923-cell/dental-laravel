import 'patient_registration.dart';

/// Mirrors one entry of `Api\PatientRegistrationQrController::stateResponse()`'s
/// `payments` array.
class PaymentEntry {
  const PaymentEntry({required this.id, required this.amount, this.paidBy, this.paidAt, this.type = 'service'});

  factory PaymentEntry.fromJson(Map<String, dynamic> json) => PaymentEntry(
        id: json['id'] as int,
        amount: double.parse(json['amount'].toString()),
        paidBy: json['paid_by'] as String?,
        paidAt: json['paid_at'] as String?,
        type: json['type'] as String? ?? 'service',
      );

  final int id;
  final double amount;
  final String? paidBy;
  final String? paidAt;

  /// `'service'` or `'lab'` (the lab screening fee, 2026-10-11).
  final String type;

  bool get isLabFee => type == 'lab';
}

/// A still-valid earlier clear result of the same patient (same phone) —
/// `data.previous_screening` (2026-10-12, see `LabFeeGate::previousScreening`).
class PreviousScreening {
  const PreviousScreening({required this.id, this.checkedAt, this.name, this.phone, this.matchedBy});

  factory PreviousScreening.fromJson(Map<String, dynamic> json) => PreviousScreening(
        id: json['id'] as int,
        checkedAt: json['checked_at'] as String?,
        name: json['name'] as String?,
        phone: json['phone'] as String?,
        matchedBy: json['matched_by'] as String?,
      );

  /// The earlier registration whose result is reused.
  final int id;
  final String? checkedAt;

  /// The earlier registration's name and phone, and whether it was found
  /// by 'phone' or only by 'name' (2026-10-12).
  final String? name;
  final String? phone;
  final String? matchedBy;

  bool get matchedByPhone => matchedBy == 'phone';
}

/// Mirrors `Api\PatientRegistrationQrController::stateResponse()` — the
/// shared response shape `scan()` and `status()` both return: a
/// registration plus whether (and how much) it's been paid. See that
/// controller's docblock for why `isPaid` is presence-of-payment only,
/// not a price-aware fully/partially-paid distinction.
class RegistrationPaymentState {
  const RegistrationPaymentState({
    required this.registration,
    required this.payments,
    required this.totalPaid,
    required this.isPaid,
    this.labFee,
    this.labPaid = false,
    this.labPaidAmount = 0,
    this.labValidityDays = 0,
    this.previousScreening,
    this.screeningCheckedAt,
    this.screeningCheckedBy,
    this.reusedFromCheckedAt,
  });

  factory RegistrationPaymentState.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return RegistrationPaymentState(
      registration: PatientRegistration.fromJson(data['registration'] as Map<String, dynamic>),
      payments: (data['payments'] as List<dynamic>)
          .map((e) => PaymentEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalPaid: double.parse(data['total_paid'].toString()),
      isPaid: data['is_paid'] as bool,
      labFee: data['lab_fee'] == null ? null : double.parse(data['lab_fee'].toString()),
      labPaid: data['lab_paid'] as bool? ?? false,
      labPaidAmount: double.tryParse('${data['lab_paid_amount'] ?? 0}') ?? 0,
      labValidityDays: (data['lab_validity_days'] as num?)?.toInt() ?? 0,
      previousScreening: data['previous_screening'] == null
          ? null
          : PreviousScreening.fromJson(data['previous_screening'] as Map<String, dynamic>),
      screeningCheckedAt: data['screening_checked_at'] as String?,
      screeningCheckedBy: data['screening_checked_by'] as String?,
      reusedFromCheckedAt: (data['reused_from'] as Map<String, dynamic>?)?['checked_at'] as String?,
    );
  }

  final PatientRegistration registration;
  final List<PaymentEntry> payments;
  final double totalPaid;
  final bool isPaid;

  /// The clinic's configured lab screening fee (null = not set) and
  /// whether this patient has paid it. Separate from [isPaid]/[totalPaid],
  /// which count service payments only.
  final double? labFee;
  final bool labPaid;

  /// What was actually paid for the lab, printed on the lab slip.
  final double labPaidAmount;

  /// Days a clear result stays valid (0 = reuse off), and — only while
  /// this registration is still pending — the earlier clear result it can
  /// reuse instead of a new test and lab fee (2026-10-12).
  final int labValidityDays;
  final PreviousScreening? previousScreening;

  /// Once a result is recorded: when, by whom, and — when an earlier
  /// result was reused instead of a new test — that test's date
  /// (2026-10-17), so a re-scanned ticket shows it was already screened.
  final String? screeningCheckedAt;
  final String? screeningCheckedBy;
  final String? reusedFromCheckedAt;

  bool get isReused => reusedFromCheckedAt != null;
}
