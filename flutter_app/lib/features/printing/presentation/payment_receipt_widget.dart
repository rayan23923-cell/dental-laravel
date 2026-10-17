import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../records/domain/payment.dart';
import 'ticket_row.dart';

/// One recorded payment's receipt (2026-10-17) — the web
/// `print/payment-receipt.blade.php` on the thermal printer, reprinted
/// from the payments list. Unlike `ReceiptWidget` (printed right after
/// taking a payment, from a registration) this is built from the
/// `Payment` row itself: receipt number, person, phone, amount, payer
/// and the payment's own date.
class PaymentReceiptWidget extends StatelessWidget {
  const PaymentReceiptWidget({
    super.key,
    required this.payment,
    this.currency,
    this.logoBytes,
    this.headerTitle,
    this.headerSubtitle,
    this.widthDots = 384,
  });

  final Payment payment;
  final String? currency;
  final Uint8List? logoBytes;
  final String? headerTitle;
  final String? headerSubtitle;
  final double widthDots;

  /// "2026-10-17 09:30" from the API's `paid_at`, or "—".
  static String formatPaidAt(String? raw) {
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    return parsed == null ? '—' : DateFormat('yyyy-MM-dd HH:mm').format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final isLab = payment.isLabFee;
    final amount = '${NumberFormat('#,##0.##', 'en_US').format(payment.amount)} ${currency ?? ''}'.trim();

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
              Image.memory(logoBytes!, width: widthDots),
              const SizedBox(height: 8),
            ],
            Text(
              (headerTitle?.isNotEmpty ?? false) ? headerTitle! : 'المستشفى التعليمي لكلية طب الأسنان',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (headerSubtitle?.isNotEmpty ?? false)
              Text(headerSubtitle!, style: const TextStyle(color: Colors.black, fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              isLab ? 'وصل دفع أجور المختبر' : 'وصل دفع',
              style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2)),
              child: Text(
                isLab ? 'تم دفع أجور المختبر' : 'تم الدفع',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            ticketTable([
              ('رقم الوصل', '#${payment.id}'),
              ('اسم المريض', payment.personName),
              if (payment.patientRegistrationPhone != null) ('الهاتف', payment.patientRegistrationPhone!),
              ('المبلغ', amount),
              if (payment.paidBy != null && payment.paidBy!.isNotEmpty) ('الدافع', payment.paidBy!),
              ('التاريخ', formatPaidAt(payment.paidAt)),
            ]),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
