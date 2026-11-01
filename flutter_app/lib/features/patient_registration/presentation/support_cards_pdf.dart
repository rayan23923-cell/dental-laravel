import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_letterhead.dart';
import '../domain/support_code.dart';

/// Care cards to print on A4 and cut (2026-11-01, by request), the twin of
/// the web `print/support-cards.blade.php`: ten cards to a page (2 × 5)
/// with dashed cut lines; the wording stays neutral on purpose.
Future<Uint8List> buildSupportCardsPdf({
  required List<SupportCode> codes,
  required String title,
  pw.ImageProvider? logo,
}) async {
  final fonts = await PdfLetterhead.load();
  final doc = pw.Document(theme: fonts.theme);
  const teal = PdfColor.fromInt(0xFF0F766E);

  pw.TextStyle reg(double size, [PdfColor? color]) => pw.TextStyle(font: fonts.regular, fontSize: size, color: color);
  pw.TextStyle bold(double size, [PdfColor? color]) => pw.TextStyle(font: fonts.bold, fontSize: size, color: color);

  pw.Widget card(SupportCode c) => pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey600, width: 0.6, style: pw.BorderStyle.dashed),
        ),
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 3),
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: teal, width: 1.2))),
              child: pw.Row(
                children: [
                  if (logo != null) ...[pw.Image(logo, height: 22), pw.SizedBox(width: 5)],
                  pw.Expanded(child: pw.Text(title, style: bold(10, teal), maxLines: 1)),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                    decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFCCFBF1), borderRadius: pw.BorderRadius.circular(8)),
                    child: pw.Text('بطاقة رعاية', style: bold(8.5, const PdfColor.fromInt(0xFF115E59))),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(child: pw.Text('رمز الرعاية', style: reg(8.5, PdfColors.grey700))),
            pw.SizedBox(height: 2),
            pw.Container(
              margin: const pw.EdgeInsets.symmetric(horizontal: 26),
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: teal, width: 1.2), borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Center(
                child: pw.Text(c.code.split('').join('  '), textDirection: pw.TextDirection.ltr, style: bold(24)),
              ),
            ),
            pw.SizedBox(height: 4),
            for (final line in const ['تُقدَّم إلى موظف التذاكر عند التسجيل.', 'تشمل أجور الخدمة وفحص المختبر.', 'صالحة لمرة واحدة فقط.'])
              pw.Text('•  $line', style: reg(8, PdfColors.grey800)),
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('دفعة ${c.batch}', style: reg(6.5, PdfColors.grey500)),
                pw.Text('#${c.id}', style: reg(6.5, PdfColors.grey500), textDirection: pw.TextDirection.ltr),
              ],
            ),
          ],
        ),
      );

  for (var start = 0; start < codes.length; start += 10) {
    final pageCodes = codes.sublist(start, (start + 10).clamp(0, codes.length));
    doc.addPage(
      pw.Page(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        build: (context) => pw.Column(
          children: [
            for (var row = 0; row < 5; row++)
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    for (var col = 0; col < 2; col++)
                      pw.Expanded(
                        child: row * 2 + col < pageCodes.length ? card(pageCodes[row * 2 + col]) : pw.SizedBox(),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
  if (codes.isEmpty) {
    doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('لا توجد أكواد فعّالة للطباعة.', style: reg(14)))));
  }

  return doc.save();
}
