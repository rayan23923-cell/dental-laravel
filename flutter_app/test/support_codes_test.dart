import 'package:dental_clinic_app/features/patient_registration/domain/patient_registration.dart';
import 'package:dental_clinic_app/features/patient_registration/domain/support_code.dart';
import 'package:dental_clinic_app/features/patient_registration/presentation/support_cards_pdf.dart';
import 'package:dental_clinic_app/features/records/domain/payment.dart';
import 'package:dental_clinic_app/features/records/presentation/payments/payments_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// Care cards (2026-11-01): the API shapes parse, the cards and the
/// report's last page build as PDFs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('codes page, registration and report rows parse; PDFs build', () async {
    final page = SupportCodePage.fromJson({
      'data': [
        {'id': 1, 'code': '12345', 'batch': 1, 'note': 'Nov', 'status': 'active', 'created_at': '2026-11-01T10:00:00Z'},
        {'id': 2, 'code': '54321', 'batch': 1, 'status': 'used', 'patient': {'id': 9, 'name': 'Ali'}},
      ],
      'meta': {'current_page': 1, 'last_page': 1, 'total': 2},
      'counts': {'all': 2, 'active': 1, 'used': 1, 'disabled': 0},
      'batches': [{'batch': 1, 'note': 'Nov', 'total': 2, 'active': 1, 'used': 1}],
      'enabled': true,
    });
    expect(page.codes.last.patientName, 'Ali');
    expect(page.counts['active'], 1);
    expect(page.enabled, isTrue);

    final r = PatientRegistration.fromJson({'id': 9, 'name': 'Ali', 'phone': '0770', 'supported': true, 'support_code': '54321', 'service_fee': 0});
    expect(r.supported, isTrue);
    expect(r.servicePrice, 0);

    final cards = await buildSupportCardsPdf(codes: page.codes, title: 'Clinic');
    expect(cards.length, greaterThan(1000));

    final report = PaymentReport.fromJson({
      'data': {
        'payments': [],
        'periods': {for (final k in ['today', 'week', 'month', 'year']) k: {'total': 0, 'count': 0}},
        'daily': [],
        'monthly': [],
        'filtered_total': 0,
        'by_source': [],
        'currency': 'IQD',
        'supported': [
          {'name': 'Ali', 'phone': '0770', 'service': 'Filling', 'code': '54321', 'waived_service': 20000, 'waived_lab': 5000, 'waived_total': 25000, 'used_at': '2026-11-01 10:00'},
        ],
        'discounted': [
          {'name': 'Sara', 'who': 'طالب', 'source': 'registration', 'full': 20000, 'percent': '50', 'paid': 10000, 'saved': 10000, 'paid_at': '2026-11-01 10:00'},
        ],
      },
    });
    expect(report.supported.single.waivedTotal, 25000);
    expect(report.discounted.single.saved, 10000);
    final pdf = await buildPaymentsReportPdf(report: report, settings: null);
    expect(pdf.length, greaterThan(1000));
  });
}
