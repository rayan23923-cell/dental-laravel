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

  doc.addPage(
    pw.Page(
      textDirection: pw.TextDirection.rtl,
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Column(
        children: [
          letterhead.build(title: 'بطاقة الطبيب', settings: settings, logo: logo),
          pw.SizedBox(height: 16),
          pw.SizedBox(width: 380, child: _doctorCard(letterhead, doctor, settings, photo)),
        ],
      ),
    ),
  );

  return doc.save();
}

/// Every given doctor's card, four to an A4 page in a 2×2 grid, like the
/// web's `print/doctor-cards.blade.php` (2026-10-18, by request). [photos]
/// is keyed by doctor id; a missing one prints the card without it.
Future<Uint8List> buildDoctorCardsPdf({
  required List<DoctorAdmin> doctors,
  required ClinicSettings? settings,
  Map<int, pw.ImageProvider> photos = const {},
}) async {
  final letterhead = await PdfLetterhead.load();
  final doc = pw.Document(theme: letterhead.theme);
  const gap = 10.0;

  for (var i = 0; i < doctors.length; i += 4) {
    final chunk = doctors.sublist(i, (i + 4).clamp(0, doctors.length));
    pw.Widget cell(int j) => pw.Expanded(
          child: j < chunk.length
              ? _doctorCard(letterhead, chunk[j], settings, photos[chunk[j].id], compact: true)
              : pw.SizedBox(),
        );
    doc.addPage(
      pw.Page(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        build: (context) => pw.Column(
          children: [
            for (final row in [0, 2]) ...[
              if (row == 2) pw.SizedBox(height: gap),
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [cell(row), pw.SizedBox(width: gap), cell(row + 1)],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  return doc.save();
}

/// One card: the indigo-bordered box with the photo, details, QR and the
/// two signature lines. [compact] is the four-to-a-page size, headed by
/// the university's name since that page has no letterhead.
pw.Widget _doctorCard(
  PdfLetterhead letterhead,
  DoctorAdmin doctor,
  ClinicSettings? settings,
  pw.ImageProvider? photo, {
  bool compact = false,
}) {
  const indigo = PdfColor.fromInt(0xFF4F46E5);
  final showGroups = settings?.groupsEnabled ?? true;
  const fontSize = 10.0;
  final photoSize = compact ? 70.0 : 80.0;
  const qrSize = 110.0;

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
        width: compact ? 90 : 140,
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey500))),
        child: pw.Text(
          label,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: letterhead.regular, fontSize: compact ? 9 : 11),
        ),
      );

  final heading = settings == null
      ? ''
      : ((settings.universityName ?? '').trim().isNotEmpty ? settings.universityName! : settings.clinicName);

  return pw.Container(
    padding: pw.EdgeInsets.all(compact ? 10 : 20),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: indigo, width: 2),
      borderRadius: pw.BorderRadius.circular(compact ? 10 : 12),
    ),
    child: pw.Column(
      children: [
        if (compact && heading.isNotEmpty)
          pw.Text(
            heading,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: letterhead.bold, fontSize: 9, color: PdfColors.grey800),
          ),
        pw.Text('بطاقة تعريف الطبيب', style: pw.TextStyle(font: letterhead.bold, fontSize: compact ? 14 : 16, color: indigo)),
        pw.SizedBox(height: compact ? 6 : 14),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (photo != null) ...[
              pw.Container(
                width: photoSize,
                height: photoSize,
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
              pw.SizedBox(width: compact ? 8 : 14),
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
                          child: pw.Text(r.$1, style: pw.TextStyle(font: letterhead.bold, fontSize: fontSize)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(r.$2, style: pw.TextStyle(font: letterhead.regular, fontSize: fontSize)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
        if (compact) pw.Spacer() else pw.SizedBox(height: 16),
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: jsonEncode({'type': 'doctor', 'id': doctor.id}),
          width: qrSize,
          height: qrSize,
          drawText: false,
        ),
        pw.SizedBox(height: compact ? 12 : 22),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [signature('توقيع الطبيب'), signature('ختم الكلية')],
        ),
      ],
    ),
  );
}
