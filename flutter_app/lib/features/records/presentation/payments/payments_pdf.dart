import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/pdf/pdf_letterhead.dart';
import '../../../clinic_settings/domain/clinic_settings.dart';
import '../../../patient_registration/domain/discount_breakdown.dart';
import '../../domain/payment.dart';
import '../../domain/payment_stats.dart';

/// PDFs of the payments pages (2026-10-17), through the `printing`
/// package: one payment's receipt (the web `print/payment-receipt`) and
/// the payments report (the web `print/payments-report`). The printed
/// text is Arabic, as on the web prints.

String _money(num v) => NumberFormat('#,##0.##', 'en_US').format(v);

/// The report's discount cell: "50% · طالب · المرحلة الرابعة"; an older
/// server's short label; or "—".
String _discountCell(Payment p) {
  final d = p.discount;
  if (d == null) return p.discountLabel ?? '—';
  return [if (d.percent != null) '${d.percent}%', d.who].where((s) => s.isNotEmpty).join(' · ');
}

String _paidAt(String? raw) {
  final parsed = raw == null ? null : DateTime.tryParse(raw);
  return parsed == null ? '—' : DateFormat('yyyy-MM-dd HH:mm').format(parsed.toLocal());
}

const _sourceLabels = {'registration': 'تسجيل مريض', 'lab': 'أجور المختبر', 'appointment': 'موعد'};

/// One payment's receipt, the web `print/payment-receipt.blade.php`.
Future<Uint8List> buildPaymentReceiptPdf({
  required Payment payment,
  required ClinicSettings? settings,
  PdfPageFormat format = PdfPageFormat.a4,
  pw.ImageProvider? logo,
}) async {
  final letterhead = await PdfLetterhead.load();
  final doc = pw.Document(theme: letterhead.theme);
  final isLab = payment.isLabFee;
  final currency = settings?.currency ?? '';

  final rows = <(String, String)>[
    ('رقم الوصل', '#${payment.id}'),
    ('اسم المريض', payment.personName),
    if (payment.patientRegistrationPhone != null) ('الهاتف', payment.patientRegistrationPhone!),
    // Student/employee discount (2026-10-25, by request).
    ...discountAmountRows(
      payment.discount,
      label: 'المبلغ',
      amountText: '${_money(payment.amount)} $currency'.trim(),
      money: (v) => '${_money(v)} $currency'.trim(),
      fallbackLine: payment.discountLine,
    ),
    if (payment.paidBy != null && payment.paidBy!.isNotEmpty) ('الدافع', payment.paidBy!),
    ('التاريخ', _paidAt(payment.paidAt)),
  ];

  doc.addPage(
    pw.Page(
      textDirection: pw.TextDirection.rtl,
      pageFormat: format,
      build: (context) => pw.Column(
        children: [
          letterhead.build(title: isLab ? 'وصل دفع أجور المختبر' : 'وصل دفع', settings: settings, logo: logo),
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
                    border: pw.Border.all(color: PdfColors.grey900, width: 2),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    isLab ? 'تم دفع أجور المختبر' : 'تم الدفع',
                    style: pw.TextStyle(font: letterhead.bold, fontSize: 20),
                  ),
                ),
                pw.SizedBox(height: 12),
                _keyValueTable(letterhead, rows),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}

pw.Widget _keyValueTable(PdfLetterhead letterhead, List<(String, String)> rows) => pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {0: pw.FlexColumnWidth(1.4), 1: pw.FlexColumnWidth(2.6)},
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
    );

/// The payments report, the web `print/payments-report.blade.php`: the
/// filters in words, the four period cards, the daily and monthly charts,
/// totals by source and every payment matching the filters with a total.
Future<Uint8List> buildPaymentsReportPdf({
  required PaymentReport report,
  required ClinicSettings? settings,
  String? search,
  String? from,
  String? to,
  String? source,
  String? title,
  PdfPageFormat format = PdfPageFormat.a4,
  pw.ImageProvider? logo,
}) async {
  final letterhead = await PdfLetterhead.load();
  final doc = pw.Document(theme: letterhead.theme);
  final stats = report.stats;
  final currency = stats.currency ?? settings?.currency ?? '';

  final filterBits = [
    if (from != null) 'من $from',
    if (to != null) 'إلى $to',
    if (source != null) 'المصدر: ${_sourceLabels[source] ?? source}',
    if (search != null && search.isNotEmpty) 'بحث: $search',
  ];
  const periodLabels = {'today': 'اليوم', 'week': 'هذا الأسبوع', 'month': 'هذا الشهر', 'year': 'هذه السنة'};

  pw.TextStyle reg(double size, [PdfColor? color]) => pw.TextStyle(font: letterhead.regular, fontSize: size, color: color);
  pw.TextStyle bold(double size) => pw.TextStyle(font: letterhead.bold, fontSize: size);

  pw.Widget cell(String text, {bool header = false, double size = 9}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(text, style: header ? bold(size) : reg(size)),
      );

  doc.addPage(
    pw.MultiPage(
      textDirection: pw.TextDirection.rtl,
      pageFormat: format,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => context.pageNumber == 1
          ? letterhead.build(title: title ?? 'تقرير المدفوعات', settings: settings, logo: logo)
          : pw.SizedBox.shrink(),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.center,
        child: pw.Text('${context.pageNumber} / ${context.pagesCount}', style: reg(8, PdfColors.grey600)),
      ),
      build: (context) => [
        if (filterBits.isNotEmpty)
          pw.Center(child: pw.Text(filterBits.join(' · '), style: reg(10, PdfColors.grey700))),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            for (final entry in periodLabels.entries) ...[
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey500),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(entry.value, style: reg(9, PdfColors.grey700)),
                      pw.Text(_money(stats.periods[entry.key]?.total ?? 0), style: bold(14)),
                      pw.Text('$currency · ${stats.periods[entry.key]?.count ?? 0} دفعة', style: reg(8, PdfColors.grey600)),
                    ],
                  ),
                ),
              ),
              if (entry.key != 'year') pw.SizedBox(width: 6),
            ],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _barChart('الوارد اليومي (آخر 30 يومًا)', stats.daily, letterhead)),
            pw.SizedBox(width: 12),
            pw.Expanded(child: _barChart('الوارد الشهري (هذه السنة)', stats.monthly, letterhead)),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          '${filterBits.isNotEmpty ? 'مجموع نتائج البحث' : 'مجموع كل المدفوعات'}: ${_money(stats.filteredTotal)} $currency',
          style: bold(12),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [cell('المصدر', header: true), cell('عدد الدفعات', header: true), cell('المبلغ', header: true)],
            ),
            for (final s in stats.bySource)
              pw.TableRow(children: [
                cell(_sourceLabels[s.source] ?? s.source),
                cell('${s.count}'),
                cell('${_money(s.total)} $currency'),
              ]),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text('المدفوعات (${report.payments.length})', style: bold(12)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(0.6),
            1: pw.FlexColumnWidth(2.2),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FlexColumnWidth(1.5),
            4: pw.FlexColumnWidth(1.1),
            5: pw.FlexColumnWidth(1.3),
            6: pw.FlexColumnWidth(1.1),
            7: pw.FlexColumnWidth(1.2),
            8: pw.FlexColumnWidth(1.6),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                for (final h in ['#', 'الشخص', 'المصدر', 'الخدمة', 'المبلغ', 'التخفيض', 'المبلغ بعد التخفيض', 'الدافع', 'التاريخ']) cell(h, header: true),
              ],
            ),
            if (report.payments.isEmpty)
              pw.TableRow(children: [
                cell(''),
                cell('لا توجد مدفوعات.'),
                for (var i = 0; i < 7; i++) cell(''),
              ]),
            for (final p in report.payments)
              pw.TableRow(children: [
                cell('${p.id}'),
                cell(p.isArchivedPatient ? '${p.personName} (مؤرشف)' : p.personName),
                cell(_sourceLabels[p.source] ?? p.source),
                cell(p.serviceName ?? '—'),
                // Student/employee discount (2026-10-25, by request): the
                // amount, the discount and the amount after it.
                cell(_money(p.discount?.full ?? p.amount)),
                cell(_discountCell(p)),
                cell(_money(p.amount), header: p.discount?.isDiscounted ?? false),
                cell(p.paidBy ?? '—'),
                cell(_paidAt(p.paidAt)),
              ]),
            if (report.payments.isNotEmpty)
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  cell(''),
                  cell('المجموع', header: true),
                  cell(''),
                  cell(''),
                  cell(''),
                  cell(''),
                  cell('${_money(stats.filteredTotal)} $currency', header: true),
                  cell(''),
                  cell(''),
                ],
              ),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

/// A plain bar chart of [points] (oldest first), the PDF twin of the web
/// `print/partials/bar-chart.blade.php`.
pw.Widget _barChart(String title, List<ChartPoint> points, PdfLetterhead letterhead) {
  const height = 90.0;
  final max = points.fold<double>(0, (m, p) => p.total > m ? p.total : m);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(title, style: pw.TextStyle(font: letterhead.bold, fontSize: 10)),
      pw.SizedBox(height: 4),
      pw.Container(
        height: height,
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.5)),
        ),
        // Oldest on the left, as on the web chart.
        child: pw.Directionality(
          textDirection: pw.TextDirection.ltr,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              for (final p in points)
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 0.6),
                    child: pw.Container(
                      height: max <= 0 ? 0 : (p.total / max) * (height - 2),
                      color: PdfColors.indigo400,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      if (points.isNotEmpty)
        pw.Directionality(
          textDirection: pw.TextDirection.ltr,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(points.first.label, style: pw.TextStyle(font: letterhead.regular, fontSize: 7, color: PdfColors.grey600)),
              // Arabic is only shaped in right-to-left text; inside this
              // left-to-right axis row it printed as loose, reversed
              // letters (2026-10-31).
              pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Text('الأعلى ${_money(max)}', style: pw.TextStyle(font: letterhead.regular, fontSize: 7, color: PdfColors.grey600)),
              ),
              pw.Text(points.last.label, style: pw.TextStyle(font: letterhead.regular, fontSize: 7, color: PdfColors.grey600)),
            ],
          ),
        ),
    ],
  );
}
