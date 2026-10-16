import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'escpos_raster.dart';
import 'windows_raw_printer.dart';

/// How the Windows app reaches the thermal printer (2026-10-16).
enum DesktopPrintMode {
  /// Through the Windows printer driver, as a PDF the width of the roll.
  driver,

  /// ESC/POS bytes straight to the chosen Windows printer queue: a USB
  /// thermal printer, crisp, and cut at the end.
  usbRaw,

  /// ESC/POS over the network to the printer's IP (port 9100 by default).
  network,
}

/// Ticket printing on the Windows app (2026-10-12, by request): the
/// Android/iOS `PosPrinterPlugin` doesn't exist there, so the rendered
/// ticket image goes to a Windows printer (the desk's thermal printer
/// through its driver) as a one-page PDF exactly as wide as the paper roll.
///
/// The printer chosen once in "إعدادات الطابعة" is used directly with no
/// dialog; until one is chosen, the Windows print dialog opens instead.
/// [DesktopPrintMode.usbRaw] and [DesktopPrintMode.network] send ESC/POS
/// instead, for printers whose driver prints blank, tiny or uncut slips.
class DesktopTicketPrinter {
  const DesktopTicketPrinter._();

  static const _kPrinterUrl = 'desktop_printer_url';
  static const _kPrinterName = 'desktop_printer_name';
  static const _kMode = 'desktop_print_mode';
  static const _kNetworkHost = 'desktop_printer_host';
  static const _kNetworkPort = 'desktop_printer_port';
  static const defaultNetworkPort = 9100;

  static Future<DesktopPrintMode> savedMode() async {
    final name = (await SharedPreferences.getInstance()).getString(_kMode);
    return DesktopPrintMode.values.firstWhere((m) => m.name == name, orElse: () => DesktopPrintMode.driver);
  }

  static Future<({String? host, int port})> savedNetworkPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    return (host: prefs.getString(_kNetworkHost), port: prefs.getInt(_kNetworkPort) ?? defaultNetworkPort);
  }

  static Future<void> saveMode(DesktopPrintMode mode) async =>
      (await SharedPreferences.getInstance()).setString(_kMode, mode.name);

  static Future<void> saveNetworkPrinter(String host, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNetworkHost, host.trim());
    await prefs.setInt(_kNetworkPort, port);
  }

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

  /// [widthDots] is the roll's printable width in dots (384 for 58mm,
  /// 576 for 80mm), used by the ESC/POS modes.
  static Future<void> printTicket(Uint8List pngBytes, {required int paperWidthMm, required int widthDots}) async {
    final prefs = await SharedPreferences.getInstance();
    switch (await savedMode()) {
      case DesktopPrintMode.usbRaw:
        final name = prefs.getString(_kPrinterName);
        if (name == null) throw const WindowsRawPrinterException('Choose the USB printer in the printer settings first.');
        WindowsRawPrinter.write(name, escPosRaster(pngBytes, widthDots: widthDots));
        return;
      case DesktopPrintMode.network:
        final printer = await savedNetworkPrinter();
        final host = printer.host;
        if (host == null || host.isEmpty) {
          throw const SocketException('Enter the network printer\'s IP address in the printer settings first.');
        }
        final socket = await Socket.connect(host, printer.port, timeout: const Duration(seconds: 5));
        try {
          socket.add(escPosRaster(pngBytes, widthDots: widthDots));
          await socket.flush();
        } finally {
          await socket.close();
          socket.destroy();
        }
        return;
      case DesktopPrintMode.driver:
        break;
    }

    final pdfBytes = await _ticketPdf(pngBytes, paperWidthMm);
    final url = prefs.getString(_kPrinterUrl);
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
