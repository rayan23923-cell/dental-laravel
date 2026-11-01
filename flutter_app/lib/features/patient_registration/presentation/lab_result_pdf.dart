import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_letterhead.dart';
import '../../clinic_settings/domain/clinic_settings.dart';
import '../domain/discount_breakdown.dart';
import '../domain/registration_payment_state.dart';

/// The full-page lab result (2026-10-17) — the web `print/lab-result.blade.php`
/// as a PDF through the `printing` package, for every platform (the
/// thermal slip stays for the POS/desktop printers): the result banner,
/// patient details, the lab fee (or "exempt" when an earlier valid result
/// was reused), check date and checker, and the patient QR.
Future<Uint8List> buildLabResultPdf({
  required RegistrationPaymentState state,
  required ClinicSettings? settings,
  PdfPageFormat format = PdfPageFormat.a4,
  pw.ImageProvider? logo,
  Uint8List? qrBytes,
}) async {
  final letterhead = await PdfLetterhead.load();
  final doc = pw.Document(theme: letterhead.theme);
  final r = state.registration;

  final (label, color, background) = switch (r.screeningStatus) {
    'clear' => ('سليم', PdfColor.fromHex('#15803d'), PdfColor.fromHex('#dcfce7')),
    'flagged' => ('غير سليم', PdfColor.fromHex('#b91c1c'), PdfColor.fromHex('#fee2e2')),
    _ => ('بانتظار الفحص', PdfColor.fromHex('#b45309'), PdfColor.fromHex('#fef3c7')),
  };

  String date(String? raw, String pattern) {
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    return parsed == null ? '—' : DateFormat(pattern).format(parsed.toLocal());
  }

  final currency = settings?.currency ?? '';
  final rows = <(String, String)>[
    ('اسم المريض', r.name),
    ('الهاتف', r.phone),
    ('الخدمة', r.serviceName ?? '—'),
    if (r.registerDayName != null) ('اليوم', r.registerDayName!),
    if (r.screeningReusedFrom != null) ...[
      ('أجور المختبر', 'معفى — فحص سابق صالح'),
      ('تاريخ الفحص السابق', date(r.screeningReusedFromCheckedAt, 'yyyy-MM-dd')),
    ] else if (r.supported) ...[
      // Free with a care card (2026-11-01, by request).
      ('أجور المختبر', '0 $currency'.trim()),
      ('الحالة', 'مشمول بالرعاية'),
    ] else if (state.labPaid) ...[
      // Student/employee discount (2026-10-25, by request).
      ...discountAmountRows(
        state.labDiscount,
        label: 'أجور المختبر',
        fullLabel: 'أجور المختبر',
        amountText: '${NumberFormat('#,##0', 'en_US').format(state.labPaidAmount)} $currency'.trim(),
        money: (v) => '${NumberFormat('#,##0', 'en_US').format(v)} $currency'.trim(),
        fallbackLine: state.labDiscountLine,
      ),
      ('الحالة', 'مدفوع'),
    ],
    ('تاريخ الفحص', date(r.screeningCheckedAt, 'yyyy-MM-dd HH:mm')),
    ('الفاحص', r.screeningCheckedByName ?? '—'),
  ];

  doc.addPage(
    pw.Page(
      textDirection: pw.TextDirection.rtl,
      pageFormat: format,
      build: (context) => pw.Column(
        children: [
          letterhead.build(title: 'نتيجة فحص المختبر', settings: settings, logo: logo),
          pw.SizedBox(height: 8),
          pw.Container(
            width: 320,
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey500),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              children: [
                pw.Container(
                  width: double.infinity,
                  alignment: pw.Alignment.center,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: background,
                    border: pw.Border.all(color: color, width: 2),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(label, style: pw.TextStyle(font: letterhead.bold, fontSize: 24, color: color)),
                ),
                pw.SizedBox(height: 12),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: const {0: pw.FlexColumnWidth(1.6), 1: pw.FlexColumnWidth(2.4)},
                  children: [
                    for (final (k, v) in rows)
                      pw.TableRow(children: [
                        pw.Container(
                          color: PdfColors.grey100,
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(k, style: pw.TextStyle(font: letterhead.bold, fontSize: 11)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(v, style: pw.TextStyle(font: letterhead.regular, fontSize: 11)),
                        ),
                      ]),
                  ],
                ),
                if (qrBytes != null) ...[
                  pw.SizedBox(height: 12),
                  pw.Image(pw.MemoryImage(qrBytes), width: 150, height: 150),
                  pw.Text('رمز المريض', style: pw.TextStyle(font: letterhead.regular, fontSize: 10, color: PdfColors.grey700)),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}
