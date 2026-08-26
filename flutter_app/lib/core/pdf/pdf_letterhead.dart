import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/clinic_settings/domain/clinic_settings.dart';
import '../network/api_client.dart';

/// Shared by every PDF report (doctors roster, group roster, task progress)
/// so the letterhead — logo, university/college name, report title, print
/// timestamp — is built once instead of three times. Mirrors the legacy
/// app's `print_doctors.php`/`task_progress_print.php` header block, minus
/// the CSS watermark trick (not attempted here — a real PDF page background
/// image achieves the same "logo behind the content" look if ever wanted,
/// but wasn't asked for).
///
/// The `pdf` package renders its own glyphs rather than using the OS text
/// renderer, so Arabic needs a bundled font — Tajawal (OFL, static
/// Regular/Bold weights, unlike most modern Google Fonts families which
/// ship variable-font-only and can't provide two Font instances the `pdf`
/// package can pick between).
class PdfLetterhead {
  PdfLetterhead._(this.theme, this.regular, this.bold);

  final pw.ThemeData theme;
  final pw.Font regular;
  final pw.Font bold;

  static PdfLetterhead? _cached;

  static Future<PdfLetterhead> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    final regularData = await rootBundle.load('assets/fonts/Tajawal-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Tajawal-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);

    return _cached = PdfLetterhead._(theme, regular, bold);
  }

  /// `settings` is nullable and every field inside it is nullable —
  /// matches `clinicSettingsProvider`'s own "branding is an enhancement,
  /// never blocks" contract (see that provider's doc comment). A missing
  /// logo/university/college name just shrinks the header, it never fails
  /// the PDF.
  pw.Widget build({required String title, ClinicSettings? settings, String? subtitle, pw.ImageProvider? logo}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo != null) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: pw.Image(logo, height: 60)),
        if (settings?.universityName != null)
          pw.Text(settings!.universityName!, style: pw.TextStyle(font: bold, fontSize: 14)),
        if (settings?.collegeName != null)
          pw.Text(settings!.collegeName!, style: pw.TextStyle(font: regular, fontSize: 12)),
        pw.SizedBox(height: 10),
        pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 18)),
        if (subtitle != null) pw.Text(subtitle, style: pw.TextStyle(font: regular, fontSize: 12)),
        pw.SizedBox(height: 4),
        pw.Text(
          DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
          style: pw.TextStyle(font: regular, fontSize: 9, color: PdfColors.grey700),
        ),
        pw.Divider(thickness: 1),
      ],
    );
  }
}

/// Fetches the logo's raw bytes (for [PdfLetterhead.build]'s `logo` param)
/// through the same authenticated client every other request uses
/// (`ApiClient.getBytes`, already proven against an absolute URL for the
/// existing QR-code-PNG call site) — never blocks the PDF if it fails.
Future<pw.ImageProvider?> loadLetterheadLogo(WidgetRef ref, ClinicSettings? settings) async {
  final url = settings?.ticketLogoUrl;
  if (url == null) return null;
  try {
    final bytes = await ref.read(apiClientProvider).getBytes(url);
    return pw.MemoryImage(Uint8List.fromList(bytes));
  } catch (_) {
    return null;
  }
}
