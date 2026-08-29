import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_letterhead.dart';
import '../../clinic_settings/domain/clinic_settings.dart';
import '../domain/task_progress_group.dart';

/// Port of `admin/task_progress_print.php`'s content as a real PDF — see
/// `pdf_letterhead.dart`'s doc comment for why this doesn't just reuse the
/// legacy `window.print()` approach. Same three scopes the legacy page's
/// three buttons opened it with (`get_group_doctors.php` lines 199/271/390):
/// whole group (both filters null), one department tab (`departmentId`),
/// one doctor row (`doctorId`, which also narrows to that doctor's own
/// department since a doctor only has rows under one department here).
///
/// Status colors/labels mirror `_TaskSlotTile._statusColor()`/
/// `_statusLabel()` in `task_progress_screen.dart` exactly, so the PDF
/// reads the same as the on-screen badges.
Future<Uint8List> buildTaskProgressPdf({
  required TaskProgressGroupDetail detail,
  required ClinicSettings? settings,
  pw.ImageProvider? logo,
  int? departmentId,
  int? doctorId,
}) async {
  final letterhead = await PdfLetterhead.load();
  final doc = pw.Document(theme: letterhead.theme);

  final departments = detail.departments
      .where((d) => departmentId == null || d.id == departmentId)
      .map((d) => doctorId == null
          ? d
          : TaskProgressDepartment(
              id: d.id,
              name: d.name,
              taskCount: d.taskCount,
              totalRequired: d.totalRequired,
              doctors: d.doctors.where((doc) => doc.id == doctorId).toList(),
            ))
      .where((d) => d.doctors.isNotEmpty)
      .toList();

  final filterLine = [
    if (departmentId != null && departments.isNotEmpty) 'القسم: ${departments.first.name}',
    if (doctorId != null && departments.isNotEmpty && departments.first.doctors.isNotEmpty)
      'الطبيب: ${departments.first.doctors.first.name}',
  ].join(' — ');

  doc.addPage(
    pw.MultiPage(
      textDirection: pw.TextDirection.rtl,
      pageFormat: PdfPageFormat.a4,
      header: (context) => context.pageNumber == 1
          ? letterhead.build(
              title: 'تقرير تقدم المهام',
              settings: settings,
              subtitle: [
                detail.groupOption.name,
                if (detail.groupOption.stageName != null) detail.groupOption.stageName!,
                if (detail.groupOption.educationTypeName != null) detail.groupOption.educationTypeName!,
                if (filterLine.isNotEmpty) filterLine,
              ].join(' · '),
              logo: logo,
            )
          : pw.SizedBox.shrink(),
      build: (context) => [
        for (final department in departments) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 8),
            child: pw.Text(department.name, style: pw.TextStyle(font: letterhead.bold, fontSize: 13)),
          ),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(0.5),
              1: pw.FlexColumnWidth(1.6),
              2: pw.FlexColumnWidth(2.2),
              3: pw.FlexColumnWidth(1.2),
              4: pw.FlexColumnWidth(1),
              5: pw.FlexColumnWidth(1),
              6: pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  for (final h in ['#', 'اسم الطبيب', 'المهمة', 'الحالة', 'درجة المهمة', 'الدرجة المحققة', 'التاريخ'])
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(h, style: pw.TextStyle(font: letterhead.bold, fontSize: 9)),
                    ),
                ],
              ),
              for (final row in _flattenRows(department.doctors))
                pw.TableRow(
                  children: [
                    _cell('${row.index}', letterhead.regular),
                    _cell(row.doctorName, letterhead.regular),
                    _cell('${row.card.taskTitle} (${row.card.slot})', letterhead.regular),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: pw.BoxDecoration(
                          color: _statusColor(row.card.status),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          _statusLabel(row.card.status),
                          style: pw.TextStyle(font: letterhead.regular, fontSize: 8, color: PdfColors.white),
                        ),
                      ),
                    ),
                    _cell(row.card.taskGrade?.toString() ?? '-', letterhead.regular),
                    _cell(row.card.grade?.toString() ?? '-', letterhead.regular),
                    _cell(row.card.completionDate ?? row.card.assignedDate ?? '-', letterhead.regular),
                  ],
                ),
            ],
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _cell(String text, pw.Font font) =>
    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 9)));

PdfColor _statusColor(String status) => switch (status) {
      'completed' => PdfColors.green,
      'assigned' => PdfColors.blue,
      'pending' => PdfColors.orange,
      _ => PdfColors.grey,
    };

String _statusLabel(String status) => switch (status) {
      'completed' => 'مكتملة',
      'assigned' => 'قيد التنفيذ',
      'pending' => 'معلّقة',
      _ => 'لم تبدأ بعد',
    };

/// One printable row: `index` starts a fresh count per doctor, matching
/// the legacy table's rowspan-per-doctor grouping. `doctorName` is only
/// set on the first row of each doctor's block (blank on the rest) — the
/// `pdf` package has no native rowspan, so this is the standard faux-merge
/// technique for a grouped table, printing the name once per doctor
/// instead of repeating it on every row (2026-08-29, by request — the
/// prior approach traded the visual merge for simplicity by repeating the
/// cell instead, which read as clutter once actually printed).
class _PrintRow {
  const _PrintRow({required this.index, required this.doctorName, required this.card});
  final int index;
  final String doctorName;
  final TaskSlotCard card;
}

List<_PrintRow> _flattenRows(List<TaskProgressDoctorRow> doctors) {
  final rows = <_PrintRow>[];
  for (final doctor in doctors) {
    for (var i = 0; i < doctor.tasks.length; i++) {
      rows.add(_PrintRow(index: i + 1, doctorName: i == 0 ? doctor.name : '', card: doctor.tasks[i]));
    }
  }
  return rows;
}
