import 'package:intl/intl.dart';

import '../../patient_registration/domain/discount_breakdown.dart';
import 'payment_stats.dart';

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
    this.serviceName,
    this.discountLine,
    this.discountLabel,
    this.discount,
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
        serviceName: (json['patient_registration'] as Map<String, dynamic>?)?['service_name'] as String?,
        discountLine: json['discount_line'] as String?,
        discountLabel: json['discount_label'] as String?,
        discount: DiscountBreakdown.fromJson(json['discount']),
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

  /// The registration's service — sent only by the payments report
  /// (`GET /payments/report`, 2026-10-17).
  final String? serviceName;

  /// Student/employee discount (2026-10-25): the receipt line, e.g.
  /// "طالب · المرحلة الرابعة — خصم 50% من 20,000", and the report's short
  /// label; null when the patient is not eligible.
  final String? discountLine;
  final String? discountLabel;

  /// The amount, the discount and the amount after it (2026-10-25).
  final DiscountBreakdown? discount;

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

/// `GET /payments/report` (2026-10-17): every payment matching the list's
/// filters plus the same overview as `/payments/stats` — the data of the
/// web `print/payments-report` page.
class PaymentReport {
  const PaymentReport({required this.payments, required this.stats, this.supported = const [], this.discounted = const []});

  factory PaymentReport.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return PaymentReport(
      payments: ((data['payments'] as List<dynamic>?) ?? const [])
          .map((e) => Payment.fromJson(e as Map<String, dynamic>))
          .toList(),
      stats: PaymentStats.fromJson(json),
      supported: ((data['supported'] as List<dynamic>?) ?? const [])
          .map((e) => SupportedReportRow.fromJson(e as Map<String, dynamic>))
          .toList(),
      discounted: ((data['discounted'] as List<dynamic>?) ?? const [])
          .map((e) => DiscountedReportRow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final List<Payment> payments;
  final PaymentStats stats;

  /// The report's last page (2026-11-01, by request): patients treated free
  /// with a care card, and the student/employee discount's beneficiaries.
  /// Empty from older servers.
  final List<SupportedReportRow> supported;
  final List<DiscountedReportRow> discounted;
}

double? _num(Object? v) => v == null ? null : double.tryParse(v.toString());

/// One care-card patient on the report's last page (2026-11-01).
class SupportedReportRow {
  const SupportedReportRow({
    required this.name,
    this.phone,
    this.service,
    required this.code,
    this.waivedService,
    this.waivedLab,
    required this.waivedTotal,
    this.usedAt,
  });

  factory SupportedReportRow.fromJson(Map<String, dynamic> json) => SupportedReportRow(
        name: json['name'] as String? ?? '—',
        phone: json['phone'] as String?,
        service: json['service'] as String?,
        code: json['code'] as String? ?? '',
        waivedService: _num(json['waived_service']),
        waivedLab: _num(json['waived_lab']),
        waivedTotal: _num(json['waived_total']) ?? 0,
        usedAt: json['used_at'] as String?,
      );

  final String name;
  final String? phone;
  final String? service;
  final String code;
  final double? waivedService;
  final double? waivedLab;
  final double waivedTotal;
  final String? usedAt;
}

/// One discounted payment on the report's last page (2026-11-01).
class DiscountedReportRow {
  const DiscountedReportRow({
    required this.name,
    required this.who,
    required this.source,
    this.full,
    this.percent,
    required this.paid,
    this.saved,
    this.paidAt,
  });

  factory DiscountedReportRow.fromJson(Map<String, dynamic> json) => DiscountedReportRow(
        name: json['name'] as String? ?? '—',
        who: json['who'] as String? ?? '',
        source: json['source'] as String? ?? 'registration',
        full: _num(json['full']),
        percent: json['percent']?.toString(),
        paid: _num(json['paid']) ?? 0,
        saved: _num(json['saved']),
        paidAt: json['paid_at'] as String?,
      );

  final String name;
  final String who;
  final String source;
  final double? full;
  final String? percent;
  final double paid;
  final double? saved;
  final String? paidAt;
}
