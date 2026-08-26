import 'package:flutter/material.dart';
// `intl` exports its own `TextDirection`-colliding symbol — same
// collision already found and fixed in `backup_screen.dart` this session.
import 'package:intl/intl.dart' hide TextDirection;

import '../../patient_registration/domain/patient_registration.dart';
import 'ticket_row.dart';

/// The payment-desk receipt — printed after `PatientRegistrationPaymentScreen`
/// takes a payment. Same fixed-width/RTL-widget approach as `TicketWidget`
/// (see its doc comment); a second template rather than a flag on
/// `TicketWidget` because the two are printed at different points in the
/// flow (registration vs. payment) and share no per-print state.
class ReceiptWidget extends StatelessWidget {
  const ReceiptWidget({
    super.key,
    required this.registration,
    required this.amountPaid,
    required this.totalPaid,
    this.widthDots = 384,
  });

  final PatientRegistration registration;
  final double amountPaid;
  final double totalPaid;

  /// See `TicketWidget.widthDots` — same 384/58mm default, 576/80mm option.
  final double widthDots;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final amountStr = NumberFormat('#,##0.##').format(amountPaid);
    final totalStr = NumberFormat('#,##0.##').format(totalPaid);

    return Container(
      width: widthDots,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'المستشفى التعليمي لكلية طب الأسنان',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Text(
              'جامعة تكريت',
              style: TextStyle(color: Colors.black, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'وصل دفع',
              style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.black, thickness: 1),
            const SizedBox(height: 8),
            ticketRow('اسم المريض', registration.name),
            ticketRow('الهاتف', registration.phone),
            ticketRow('الخدمة', registration.serviceName ?? '—'),
            ticketRow('اليوم', registration.registerDayName ?? '—'),
            const SizedBox(height: 8),
            const Divider(color: Colors.black, thickness: 1),
            const SizedBox(height: 8),
            ticketRow('المبلغ المدفوع', amountStr),
            ticketRow('إجمالي المدفوع', totalStr),
            const SizedBox(height: 8),
            const Divider(color: Colors.black, thickness: 1),
            const SizedBox(height: 8),
            Text(dateStr, style: const TextStyle(color: Colors.black, fontSize: 14)),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
