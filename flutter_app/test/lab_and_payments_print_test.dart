import 'package:dental_clinic_app/core/network/paginated.dart';
import 'package:dental_clinic_app/features/patient_registration/domain/lab_registration.dart';
import 'package:dental_clinic_app/features/patient_registration/domain/registration_payment_state.dart';
import 'package:dental_clinic_app/features/patient_registration/presentation/lab_result_pdf.dart';
import 'package:dental_clinic_app/features/records/domain/payment.dart';
import 'package:dental_clinic_app/features/records/presentation/payments/payments_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// The lab list, payment prints and registry archive (2026-10-17): the
/// API shapes parse, and the PDFs build (Arabic font included).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final labJson = {
    'data': [
      {
        'id': 7,
        'name': 'Ali',
        'phone': '0771',
        'screening_status': 'pending',
        'service': {'id': 1, 'name': 'Filling', 'price': 25000},
        'lab_paid': false,
        'previous_screening': {'id': 3, 'checked_at': '2026-10-10T09:00:00Z', 'name': 'Ali', 'phone': '0771', 'matched_by': 'phone'},
      },
      {'id': 8, 'name': 'Sara', 'phone': '0772', 'screening_status': 'clear', 'lab_paid': true, 'previous_screening': null},
    ],
    'meta': {
      'current_page': 1,
      'last_page': 2,
      'total': 21,
      'counts': {'pending': 15, 'clear': 6},
      'lab_fee': 5000,
      'currency': 'IQD',
      'validity_days': 30,
      'can_confirm': true,
    },
  };

  final paymentJson = {
    'id': 12,
    'appointment_id': null,
    'patient_registration_id': 7,
    'type': 'lab',
    'amount': '5000.00',
    'paid_by': 'Ali',
    'paid_at': '2026-10-17T08:30:00Z',
    'appointment': null,
    'patient_registration': {'id': 7, 'name': 'Ali', 'phone': '0771', 'deleted_at': null, 'service_name': 'Filling'},
  };

  final reportJson = {
    'data': {
      'payments': [paymentJson],
      'periods': {
        'today': {'total': 5000, 'count': 1},
        'week': {'total': 5000, 'count': 1},
        'month': {'total': 5000, 'count': 1},
        'year': {'total': 5000, 'count': 1},
      },
      'daily': [for (var i = 0; i < 30; i++) {'label': '$i', 'total': i == 29 ? 5000 : 0}],
      'monthly': [for (var i = 1; i <= 12; i++) {'label': '$i', 'total': i == 10 ? 5000 : 0}],
      'filtered_total': 5000,
      'by_source': [
        {'source': 'registration', 'total': 0, 'count': 0},
        {'source': 'lab', 'total': 5000, 'count': 1},
      ],
      'currency': 'IQD',
    },
  };

  test('lab page parses rows, counts and the earlier-valid badge', () {
    final page = LabPage.fromJson(labJson);
    expect(page.items, hasLength(2));
    expect(page.items.first.canReuse, isTrue);
    expect(page.items.first.previousScreening!.matchedByPhone, isTrue);
    expect(page.items.last.canReuse, isFalse);
    expect(page.items.last.labPaid, isTrue);
    expect(page.countFor('pending'), 15);
    expect(page.countFor('flagged'), 0);
    expect(page.countFor('all'), 21);
    expect(page.labFee, 5000);
    expect(page.canConfirm, isTrue);
    expect(page.lastPage, 2);
  });

  test('paginated reads the total', () {
    final page = Paginated.fromJson(labJson, (j) => j['id'] as int);
    expect(page.total, 21);
    expect(Paginated.fromJson({'data': [1, 2].map((i) => {'id': i}).toList()}, (j) => j['id'] as int).total, 2);
  });

  test('payments report parses payments with their service and the overview', () {
    final report = PaymentReport.fromJson(reportJson);
    expect(report.payments.single.serviceName, 'Filling');
    expect(report.payments.single.isLabFee, isTrue);
    expect(report.stats.filteredTotal, 5000);
    expect(report.stats.daily, hasLength(30));
  });

  test('receipt, report and lab result PDFs build', () async {
    final payment = Payment.fromJson(paymentJson);
    final receipt = await buildPaymentReceiptPdf(payment: payment, settings: null);
    expect(String.fromCharCodes(receipt.take(4)), '%PDF');

    final report = await buildPaymentsReportPdf(
      report: PaymentReport.fromJson(reportJson),
      settings: null,
      from: '2026-10-01',
      source: 'lab',
    );
    expect(String.fromCharCodes(report.take(4)), '%PDF');

    final state = RegistrationPaymentState.fromJson({
      'data': {
        'registration': {
          'id': 7,
          'name': 'Ali',
          'phone': '0771',
          'screening_status': 'clear',
          'screening_checked_at': '2026-10-17T08:30:00Z',
          'screening_checked_by': {'id': 1, 'full_name': 'Hana'},
        },
        'payments': [
          {'id': 12, 'type': 'lab', 'amount': '5000.00', 'paid_by': null, 'paid_at': '2026-10-17T08:30:00Z'},
        ],
        'total_paid': 0,
        'is_paid': false,
        'lab_fee': 5000,
        'lab_paid': true,
        'lab_paid_amount': 5000,
        'lab_validity_days': 30,
        'previous_screening': null,
      },
    });
    final lab = await buildLabResultPdf(state: state, settings: null);
    expect(String.fromCharCodes(lab.take(4)), '%PDF');
  });
}
