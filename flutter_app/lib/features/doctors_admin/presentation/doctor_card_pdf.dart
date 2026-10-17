import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_letterhead.dart';
import '../../clinic_settings/domain/clinic_settings.dart';
import '../domain/doctor_admin.dart';

/// The doctor's ID card as a PDF (2026-10-17) — the app's take on the
/// web's `print/doctor-card.blade.php`: the letterhead, an indigo-bordered
/// card titled "بطاقة تعريف الطبيب" with the photo and the doctor's
/// details, their QR (`{"type":"doctor","id":…}`, the same payload the
/// web prints, which the task-progress scanner opens as this doctor) and
/// the two signature lines.
Future<Uint8List> buildDoctorCardPdf({
  required DoctorAdmin doctor,
  required ClinicSettings? settings,
  pw.ImageProvider? logo,
  pw.ImageProvider? photo,
}) async {
  final letterhead = await PdfLetterhead.load();
  final doc = pw.Document(theme: letterhead.theme);
  const indigo = PdfColor.fromInt(0xFF4F46E5);
  final showGroups = settings?.groupsEnabled ?? true;

  String orDash(String? v) => v == null || v.trim().isEmpty ? '-' : v;
  final rows = [
    ('الاسم', doctor.name),
    ('اسم المستخدم', doctor.username),
    ('البريد الإلكتروني', doctor.email),
    ('رقم الهاتف', orDash(doctor.phone)),
    ('نوع الدراسة', orDash(doctor.educationTypeName)),
    ('المرحلة', orDash(doctor.stageName)),
    if (showGroups) ('المجموعة', orDash(doctor.groupNames.join('، '))),
  ];

  pw.Widget signature(String label) => pw.Container(
        width: 140,
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey500))),
        child: pw.Text(label, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: letterhead.regular, fontSize: 11)),
      );

  doc.addPage(
    pw.Page(
      textDirection: pw.TextDirection.rtl,
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Column(
        children: [
          letterhead.build(title: 'بطاقة الطبيب', settings: settings, logo: logo),
          pw.SizedBox(height: 16),
          pw.Container(
            width: 380,
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: indigo, width: 2),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Column(
              children: [
                pw.Text('بطاقة تعريف الطبيب', style: pw.TextStyle(font: letterhead.bold, fontSize: 16, color: indigo)),
                pw.SizedBox(height: 14),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (photo != null) ...[
                      pw.Container(
                        width: 80,
                        height: 80,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey400),
                          borderRadius: pw.BorderRadius.circular(8),
                        ),
                        child: pw.ClipRRect(
                          horizontalRadius: 8,
                          verticalRadius: 8,
                          child: pw.Image(photo, fit: pw.BoxFit.cover),
                        ),
                      ),
                      pw.SizedBox(width: 14),
                    ],
                    pw.Expanded(
                      child: pw.Table(
                        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                        columnWidths: const {0: pw.FlexColumnWidth(1.3), 1: pw.FlexColumnWidth(2.2)},
                        children: [
                          for (final r in rows)
                            pw.TableRow(
                              children: [
                                pw.Container(
                                  color: PdfColors.grey100,
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Text(r.$1, style: pw.TextStyle(font: letterhead.bold, fontSize: 10)),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Text(r.$2, style: pw.TextStyle(font: letterhead.regular, fontSize: 10)),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: jsonEncode({'type': 'doctor', 'id': doctor.id}),
                  width: 110,
                  height: 110,
                  drawText: false,
                ),
                pw.SizedBox(height: 22),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [signature('توقيع الطبيب'), signature('ختم الكلية')],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}
