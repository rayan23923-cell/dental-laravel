import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_letterhead.dart';
import '../../clinic_settings/domain/clinic_settings.dart';
import '../domain/group_admin.dart';

/// No legacy precedent — `dental_clinics2` has no standalone group-print
/// file (its only "group" print is the task-progress report scoped to a
/// group, a separate feature already covered by `task_progress_pdf.dart`).
/// This is a new roster PDF, directly analogous to
/// `doctor_roster_pdf.dart`: group name/stage, weekly schedule, member
/// list — the group-detail screen already has all of it loaded.
Future<Uint8List> buildGroupRosterPdf({
  required GroupAdmin group,
  required ClinicSettings? settings,
  pw.ImageProvider? logo,
}) async {
  final letterhead = await PdfLetterhead.load();
  final doc = pw.Document(theme: letterhead.theme);

  doc.addPage(
    pw.MultiPage(
      textDirection: pw.TextDirection.rtl,
      pageFormat: PdfPageFormat.a4,
      header: (context) => context.pageNumber == 1
          ? letterhead.build(title: 'بيانات المجموعة', settings: settings, subtitle: group.name, logo: logo)
          : pw.SizedBox.shrink(),
      build: (context) => [
        pw.Text('المرحلة: ${group.stageName ?? 'غير محدد'}', style: pw.TextStyle(font: letterhead.bold, fontSize: 12)),
        pw.SizedBox(height: 12),
        pw.Text('المواعيد الأسبوعية', style: pw.TextStyle(font: letterhead.bold, fontSize: 13)),
        pw.SizedBox(height: 6),
        if (group.slots.isEmpty)
          pw.Text('لا توجد مواعيد مسجلة.', style: pw.TextStyle(font: letterhead.regular, fontSize: 10))
        else
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  for (final h in ['اليوم', 'من', 'إلى'])
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(h, style: pw.TextStyle(font: letterhead.bold, fontSize: 10)),
                    ),
                ],
              ),
              for (final slot in group.slots)
                pw.TableRow(
                  children: [
                    for (final cell in [slot.day, slot.startTime, slot.endTime])
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(cell, style: pw.TextStyle(font: letterhead.regular, fontSize: 9)),
                      ),
                  ],
                ),
            ],
          ),
        pw.SizedBox(height: 16),
        pw.Text(
          'أعضاء المجموعة (${group.members.length})',
          style: pw.TextStyle(font: letterhead.bold, fontSize: 13),
        ),
        pw.SizedBox(height: 6),
        if (group.members.isEmpty)
          pw.Text('لا يوجد أطباء في هذه المجموعة.', style: pw.TextStyle(font: letterhead.regular, fontSize: 10))
        else
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(0.6),
              1: pw.FlexColumnWidth(2.2),
              2: pw.FlexColumnWidth(1.8),
              3: pw.FlexColumnWidth(2.4),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  for (final h in ['#', 'الاسم', 'اسم المستخدم', 'البريد الإلكتروني'])
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(h, style: pw.TextStyle(font: letterhead.bold, fontSize: 10)),
                    ),
                ],
              ),
              for (var i = 0; i < group.members.length; i++)
                pw.TableRow(
                  children: [
                    for (final cell in [
                      '${i + 1}',
                      group.members[i].name,
                      group.members[i].username,
                      group.members[i].email,
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
    ),
  );

  return doc.save();
}
