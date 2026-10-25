import 'dart:typed_data';

import 'package:flutter/material.dart';
// `intl` exports its own `TextDirection`-colliding symbol — same
// collision already found and fixed in `backup_screen.dart` this session.
import 'package:intl/intl.dart' hide TextDirection;

import '../../patient_registration/domain/discount_breakdown.dart';
import '../../patient_registration/domain/patient_registration.dart';
import 'ticket_row.dart';

/// The printed ticket's layout. Logical-pixel width matches
/// `ticket_renderer.dart`'s `pixelRatio: 1.0` capture — the printer's
/// raster width in dots, 384 for 58mm paper or 576 for 80mm (see
/// `PrinterSettings.dotsPerLine`), defaulting to 384 to preserve the
/// exact pre-printer-settings behavior for any caller that doesn't pass
/// one. Rendered as a real widget (not raw ESC/POS text) specifically so
/// Arabic text gets real font shaping — see `PosPrinterService`'s doc
/// comment for why that matters here.
class TicketWidget extends StatelessWidget {
  const TicketWidget({
    super.key,
    required this.registration,
    this.qrBytes,
    this.logoBytes,
    this.headerTitle,
    this.headerSubtitle,
    this.resultBanner,
    this.extraRows = const [],
    this.qrCaption = 'رمز المريض',
    this.showPaid = false,
    this.widthDots = 384,
  });

  /// Big boxed line under the header — the lab slip's result ("سليم" /
  /// "غير سليم", 2026-10-11). Null on the ordinary registration ticket.
  final String? resultBanner;

  /// Rows appended after the standard four (e.g. the lab slip's payment
  /// status and check time).
  final List<(String, String)> extraRows;

  final String qrCaption;

  /// The registration ticket is printed only after payment, which is the
  /// service's price in full (2026-10-12), so it shows the amount paid and
  /// "مدفوع". Off for the lab slip, which reuses this layout.
  final bool showPaid;

  final PatientRegistration registration;

  /// The desk-payment QR (`GET /patient-registrations/{id}/qr`), fetched
  /// server-side and passed in as raw PNG bytes — see Phase 5's plan for
  /// why generation stays server-side (single source of truth, no new
  /// Flutter QR-generation dependency). Null while offline/failed to
  /// fetch — the ticket still prints, just without the QR, since a print
  /// failure must never block a registration that already succeeded.
  final Uint8List? qrBytes;

  /// The teaching hospital's logo (`ClinicSettings.logoUrl`), fetched by
  /// the caller as raw bytes the same way [qrBytes] already is — an
  /// admin-uploaded, mutable image, so it's fetched fresh rather than
  /// bundled as an asset. Same fail-open contract as [qrBytes]: null
  /// (offline, unset, fetch failure) just omits the logo, never blocks
  /// printing.
  final Uint8List? logoBytes;

  /// Big/small header lines — normally `ClinicSettings.universityName ?:
  /// clinicName` / `.collegeName` (the same pair `print/layout.blade.php`'s
  /// letterhead already uses), fetched by the caller alongside [logoBytes].
  /// Null or empty falls back to the original hard-coded strings below —
  /// never blocks printing if settings fetch fails or nothing's configured.
  final String? headerTitle;
  final String? headerSubtitle;

  final double widthDots;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    // Scales with paper width instead of a flat pixel size, so it stays
    // proportionate at both 58mm (384 dots) and 80mm (576 dots) — a flat
    // bump would be oversized on 58mm or undersized on 80mm. Bumped
    // 0.55 -> 0.75 (2026-08-26): this exact code is what both the payment
    // scan and the infectious-disease screening scan point their camera
    // at, and a bigger code is easier to scan reliably (especially on
    // older/cheaper devices, e.g. the Q2i POS terminal) at any distance.
    final qrSize = widthDots * 0.75;

    return Container(
      width: widthDots,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (logoBytes != null) ...[
              // Full paper width (2026-08-29, by request — was a fixed
              // 72x72 regardless of `widthDots`, a small fraction of the
              // real paper width). Height omitted so `Image` preserves the
              // logo's own aspect ratio instead of squashing it square.
              Image.memory(logoBytes!, width: widthDots),
              const SizedBox(height: 8),
            ],
            Text(
              (headerTitle?.isNotEmpty ?? false) ? headerTitle! : 'المستشفى التعليمي لكلية طب الأسنان',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              (headerSubtitle?.isNotEmpty ?? false) ? headerSubtitle! : 'جامعة تكريت',
              style: const TextStyle(color: Colors.black, fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.black, thickness: 1),
            const SizedBox(height: 8),
            if (resultBanner != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 3)),
                child: Text(
                  resultBanner!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black, fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
            ],
            ticketTable([
              ('اسم المريض', registration.name),
              ('الهاتف', registration.phone),
              ('الخدمة', registration.serviceName ?? '—'),
              if (registration.registerDayName != null) ('اليوم', registration.registerDayName!),
              if (showPaid && (registration.servicePrice ?? 0) > 0) ...[
                // Student/employee discount (2026-10-25, by request).
                ...discountAmountRows(
                  registration.discount,
                  label: 'المبلغ المدفوع',
                  amountText: NumberFormat('#,##0.##').format(registration.servicePrice),
                  money: NumberFormat('#,##0.##').format,
                  fallbackLine: registration.discountLine,
                ),
                ('الحالة', 'مدفوع'),
              ],
              ...extraRows,
            ]),
            const SizedBox(height: 8),
            const Divider(color: Colors.black, thickness: 1),
            const SizedBox(height: 8),
            Text(dateStr, style: const TextStyle(color: Colors.black, fontSize: 16)),
            if (qrBytes != null) ...[
              const SizedBox(height: 12),
              Image.memory(qrBytes!, width: qrSize, height: qrSize),
              Text(
                qrCaption,
                style: const TextStyle(color: Colors.black, fontSize: 14),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
