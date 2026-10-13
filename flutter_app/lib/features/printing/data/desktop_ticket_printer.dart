import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ticket printing on the Windows app (2026-10-12, by request): the
/// Android/iOS `PosPrinterPlugin` doesn't exist there, so the rendered
/// ticket image goes to a Windows printer (the desk's thermal printer
/// through its driver) as a one-page PDF exactly as wide as the paper roll.
///
/// The printer chosen once in "إعدادات الطابعة" is used directly with no
/// dialog; until one is chosen, the Windows print dialog opens instead.
class DesktopTicketPrinter {
  const DesktopTicketPrinter._();

  static const _kPrinterUrl = 'desktop_printer_url';
  static const _kPrinterName = 'desktop_printer_name';

  /// The saved printer's display name, or null when none is chosen.
  static Future<String?> savedPrinterName() async =>
      (await SharedPreferences.getInstance()).getString(_kPrinterName);

  /// Opens the Windows printer list and remembers the choice.
  static Future<String?> pickPrinter(BuildContext context) async {
    final printer = await Printing.pickPrinter(context: context);
    if (printer == null) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrinterUrl, printer.url);
    await prefs.setString(_kPrinterName, printer.name);
    return printer.name;
  }

  static Future<void> clearPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrinterUrl);
    await prefs.remove(_kPrinterName);
  }

  static Future<void> printTicket(Uint8List pngBytes, {required int paperWidthMm}) async {
    final pdfBytes = await _ticketPdf(pngBytes, paperWidthMm);
    final url = (await SharedPreferences.getInstance()).getString(_kPrinterUrl);

    if (url != null) {
      final printed = await Printing.directPrintPdf(
        printer: Printer(url: url),
        name: 'ticket',
        onLayout: (_) async => pdfBytes,
      );
      if (printed) return;
    }
    await Printing.layoutPdf(name: 'ticket', onLayout: (_) async => pdfBytes);
  }

  /// One page, the roll's width, as tall as the ticket image.
  static Future<Uint8List> _ticketPdf(Uint8List pngBytes, int paperWidthMm) async {
    final image = pw.MemoryImage(pngBytes);
    final width = paperWidthMm * PdfPageFormat.mm;
    final ratio = (image.height ?? 1) / (image.width ?? 1);
    final doc = pw.Document()
      ..addPage(
        pw.Page(
          pageFormat: PdfPageFormat(width, width * ratio, marginAll: 0),
          build: (_) => pw.Image(image, width: width, fit: pw.BoxFit.fitWidth),
        ),
      );
    return doc.save();
  }
}
