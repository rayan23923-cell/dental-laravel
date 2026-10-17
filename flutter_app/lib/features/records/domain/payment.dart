import 'package:intl/intl.dart';

/// Amounts as the web shows them (2026-10-17): grouped, no decimals, with
/// the clinic's currency after the number when one is set. Wrapped in an
/// LTR isolate so the number keeps its order inside Arabic text.
String formatMoney(num amount, [String? currency]) {
  final number = NumberFormat('#,##0', 'en_US').format(amount);
  final unit = (currency ?? '').trim();
  return unit.isEmpty ? '\u2066$number\u2069' : '\u2066$number\u2069 $unit';
}

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
    this.patientRegistrationDeletedAt,
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
        patientRegistrationDeletedAt: (json['patient_registration'] as Map<String, dynamic>?)?['deleted_at'] as String?,
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

  /// `'service'` or `'lab'` (the lab screening fee, 2026-10-11) — ignored
  /// until 2026-10-17, so lab fees showed as registration payments.
  final String type;

  /// Set when the patient was archived (soft-deleted); the payment still
  /// counts and is still listed, marked "archived" as on the web.
  final String? patientRegistrationDeletedAt;

  bool get isLabFee => type == 'lab';
  bool get isArchivedPatient => patientRegistrationDeletedAt != null;

  /// Same rule as the web `Payments/Index.vue`'s `sourceOf()`: 'lab',
  /// 'appointment' (older payments only — appointments stopped being a
  /// payments source on 2026-10-14) or 'registration'.
  String get source => isLabFee ? 'lab' : (appointmentId != null ? 'appointment' : 'registration');

  /// The person this payment settles for, regardless of source —
  /// appointment- or registration-linked alike.
  String get personName => patientRegistrationName ?? appointmentFullName ?? '—';
}
