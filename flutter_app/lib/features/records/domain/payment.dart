/// Mirrors `App\Http\Resources\PaymentResource`.
class Payment {
  const Payment({
    required this.id,
    required this.appointmentId,
    required this.amount,
    required this.paidBy,
    required this.paidAt,
    required this.appointmentFullName,
    required this.patientRegistrationId,
    required this.patientRegistrationName,
    required this.patientRegistrationPhone,
    this.type = 'service',
  });

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as int,
        appointmentId: json['appointment_id'] as int?,
        // Laravel's decimal cast serializes to a JSON *string* ("5000.00"),
        // not a number — `as num?` threw a runtime type-cast error here on
        // every real payment response, silently caught by the generic
        // "تعذر تسجيل الدفع." error path (not `ApiException`, so no useful
        // message ever surfaced). Found live via the desk-payment flow
        // (Phase 5) actually calling `createPayment()` for the first time
        // end-to-end in this app.
        amount: double.tryParse(json['amount'].toString()) ?? 0,
        paidBy: json['paid_by'] as String?,
        paidAt: json['paid_at'] as String?,
        appointmentFullName: (json['appointment'] as Map<String, dynamic>?)?['full_name'] as String?,
        patientRegistrationId: json['patient_registration_id'] as int?,
        patientRegistrationName: (json['patient_registration'] as Map<String, dynamic>?)?['name'] as String?,
        patientRegistrationPhone: (json['patient_registration'] as Map<String, dynamic>?)?['phone'] as String?,
        type: json['type'] as String? ?? 'service',
      );

  final int id;
  final int? appointmentId;
  final double amount;
  final String? paidBy;
  final String? paidAt;
  final String? appointmentFullName;
  final int? patientRegistrationId;
  final String? patientRegistrationName;
  final String? patientRegistrationPhone;

  /// `'service'` or `'lab'` (the lab screening fee).
  final String type;

  bool get isLabFee => type == 'lab';

  /// The person this payment settles for, regardless of source —
  /// appointment- or registration-linked alike.
  String get personName => patientRegistrationName ?? appointmentFullName ?? '—';
}
