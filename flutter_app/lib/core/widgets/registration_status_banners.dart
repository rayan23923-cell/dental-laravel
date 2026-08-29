import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../features/patient_registration/domain/patient_registration.dart';
import '../../features/patient_registration/domain/registration_payment_state.dart';

/// Blocks payment entirely until the infectious-disease/viral-hepatitis
/// screening comes back "سليم" — pure UX (the real enforcement is
/// `PatientScreeningGate` server-side). The "غير سليم" (flagged) case gets
/// its own message since it's a deliberate refusal, not just "not checked
/// yet". Extracted (2026-08-29) from `PatientRegistrationPaymentScreen`
/// (the reception-desk payment flow) so `PaymentFormScreen` (the general
/// front-desk payment flow) can show the identical banner instead of its
/// own drifting copy.
class ScreeningBlockedBanner extends StatelessWidget {
  const ScreeningBlockedBanner({super.key, required this.registration});

  final PatientRegistration registration;

  @override
  Widget build(BuildContext context) {
    final flagged = registration.screeningStatus == 'flagged';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.coronavirus_outlined, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              flagged
                  ? 'لا يمكن الدفع — نتيجة فحص المريض غير سليمة.'
                  : 'لا يمكن الدفع قبل تأكيد سلامة المريض من الأمراض المعدية عبر فحص المختبر.',
              style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Whether a registration has already been paid, and how much — shown
/// unconditionally (not just when blocked) so "لم يخبرني هل قام بالدفع"
/// (didn't tell me whether they'd already paid) can never happen again.
/// Same extraction history as [ScreeningBlockedBanner].
class PaidBanner extends StatelessWidget {
  const PaidBanner({super.key, required this.state});

  final RegistrationPaymentState state;

  @override
  Widget build(BuildContext context) {
    final color = state.isPaid ? Colors.green : Colors.amber;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        border: Border.all(color: color.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(state.isPaid ? Icons.check_circle : Icons.warning_amber, color: color.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.isPaid
                  ? 'تم الدفع — إجمالي المدفوع: ${NumberFormat('#,##0.##').format(state.totalPaid)}'
                  : 'لم يتم الدفع',
              style: TextStyle(color: color.shade900, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
