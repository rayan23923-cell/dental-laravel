import 'patient_registration.dart';

/// Mirrors one entry of `Api\PatientRegistrationQrController::stateResponse()`'s
/// `payments` array.
class PaymentEntry {
  const PaymentEntry({required this.id, required this.amount, this.paidBy, this.paidAt});

  factory PaymentEntry.fromJson(Map<String, dynamic> json) => PaymentEntry(
        id: json['id'] as int,
        amount: double.parse(json['amount'].toString()),
        paidBy: json['paid_by'] as String?,
        paidAt: json['paid_at'] as String?,
      );

  final int id;
  final double amount;
  final String? paidBy;
  final String? paidAt;
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
    );
  }

  final PatientRegistration registration;
  final List<PaymentEntry> payments;
  final double totalPaid;
  final bool isPaid;
}
