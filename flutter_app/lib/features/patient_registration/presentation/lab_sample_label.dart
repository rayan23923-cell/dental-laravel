import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// The sheet printed when the lab starts a patient's test (2026-11-01, by
/// request): the patient's name on top and a large circle reading "هنا توضع
/// العينات", so the samples sit on the sheet with the right name and are
/// never mixed up. Same white, fixed-width raster as `TicketWidget`.
class LabSampleLabel extends StatelessWidget {
  const LabSampleLabel({
    super.key,
    required this.patientName,
    required this.title,
    required this.circleText,
    this.subtitle,
    this.qrBytes,
    this.qrCaption,
    this.widthDots = 384,
  });

  final String patientName;
  final String title;
  final String circleText;
  final String? subtitle;

  /// The patient's QR (2026-11-01, by request): scanned when the result is
  /// ready to open the patient, pick the result and take the fee.
  final Uint8List? qrBytes;
  final String? qrCaption;
  final double widthDots;

  @override
  Widget build(BuildContext context) {
    final circle = widthDots * 0.85;
    const black = Colors.black;
    return Container(
      width: widthDots,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: black, fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(border: Border.all(color: black, width: 3)),
              child: Text(
                patientName,
                textAlign: TextAlign.center,
                style: const TextStyle(color: black, fontSize: 36, fontWeight: FontWeight.w800, height: 1.3),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: black, fontSize: 18)),
            ],
            const SizedBox(height: 18),
            Container(
              width: circle,
              height: circle,
              alignment: Alignment.center,
              padding: EdgeInsets.all(circle * 0.12),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: black, width: 5)),
              child: Text(
                circleText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: black, fontSize: 30, fontWeight: FontWeight.w700, height: 1.4),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              patientName,
              textAlign: TextAlign.center,
              style: const TextStyle(color: black, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()), style: const TextStyle(color: black, fontSize: 16)),
            ),
            if (qrBytes != null) ...[
              const SizedBox(height: 10),
              Image.memory(qrBytes!, width: widthDots * 0.55, height: widthDots * 0.55, filterQuality: FilterQuality.none),
              if (qrCaption != null) Text(qrCaption!, style: const TextStyle(color: black, fontSize: 16)),
            ],
          ],
        ),
      ),
    );
  }
}
