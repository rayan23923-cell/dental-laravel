import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_letterhead.dart';
import '../../clinic_settings/domain/clinic_settings.dart';
import '../domain/doctor_admin.dart';

/// Port of `admin/print_doctors.php`'s content (a per-stage grouped roster
/// plus a summary box) as a real PDF instead of a `window.print()` HTML
/// page — see `pdf_letterhead.dart`'s doc comment for why. Takes whatever
/// list the caller already has on screen (the currently filtered/searched
/// doctors), matching the legacy page's "طباعة الفلتر" button rather than
/// always re-fetching everything.
Future<Uint8List> buildDoctorRosterPdf({
  required List<DoctorAdmin> doctors,
  required ClinicSettings? settings,
  pw.ImageProvider? logo,
}) async {
  final letterhead = await PdfLetterhead.load();
  final doc = pw.Document(theme: letterhead.theme);

  final byStage = <String, List<DoctorAdmin>>{};
  for (final d in doctors) {
    (byStage[d.stageName ?? 'غير محدد'] ??= []).add(d);
  }

  final grouped = doctors.where((d) => d.groupNames.isNotEmpty).length;
  // No group column or counts while groups are turned off (2026-10-13).
  final showGroups = settings?.groupsEnabled ?? true;

  doc.addPage(
    pw.MultiPage(
      textDirection: pw.TextDirection.rtl,
      pageFormat: PdfPageFormat.a4,
      header: (context) => context.pageNumber == 1
          ? letterhead.build(title: 'قائمة الأطباء', settings: settings, logo: logo)
          : pw.SizedBox.shrink(),
      build: (context) => [
        for (final entry in byStage.entries) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 8),
            child: pw.Text(
              'المرحلة: ${entry.key} (${entry.value.length} طبيب/ة)',
              style: pw.TextStyle(font: letterhead.bold, fontSize: 13),
            ),
          ),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.6),
              1: const pw.FlexColumnWidth(2.2),
              2: const pw.FlexColumnWidth(2.4),
              3: const pw.FlexColumnWidth(1.6),
              if (showGroups) 4: const pw.FlexColumnWidth(1.8),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  for (final h in ['#', 'الاسم', 'البريد الإلكتروني', 'نوع التعليم', if (showGroups) 'المجموعة'])
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(h, style: pw.TextStyle(font: letterhead.bold, fontSize: 10)),
                    ),
                ],
              ),
              for (var i = 0; i < entry.value.length; i++)
                pw.TableRow(
                  children: [
                    for (final cell in [
                      '${i + 1}',
                      entry.value[i].name,
                      entry.value[i].email,
                      entry.value[i].educationTypeName ?? '',
                      if (showGroups) entry.value[i].groupNames.join('، '),
                    ])
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(cell, style: pw.TextStyle(font: letterhead.regular, fontSize: 9)),
                      ),
                  ],
                ),
            ],
          ),
        ],
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('الإجمالي الكلي: ${doctors.length}', style: pw.TextStyle(font: letterhead.bold, fontSize: 11)),
              if (showGroups) ...[
                pw.Text('عدد الأطباء المجمعين: $grouped', style: pw.TextStyle(font: letterhead.regular, fontSize: 10)),
                pw.Text(
                  'عدد الأطباء غير المجمعين: ${doctors.length - grouped}',
                  style: pw.TextStyle(font: letterhead.regular, fontSize: 10),
                ),
              ],
              if (byStage.length > 1)
                for (final entry in byStage.entries)
                  pw.Text(
                    '${entry.key}: ${entry.value.length}',
                    style: pw.TextStyle(font: letterhead.regular, fontSize: 9, color: PdfColors.grey700),
                  ),
            ],
          ),
        ),
      ],
    ),
  );

  return doc.save();
}
