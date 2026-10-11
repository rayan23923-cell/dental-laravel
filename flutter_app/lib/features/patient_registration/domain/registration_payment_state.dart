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
}
