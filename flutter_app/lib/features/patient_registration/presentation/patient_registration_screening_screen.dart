import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/patient_registration_repository.dart';
import '../domain/registration_payment_state.dart';

/// The lab/reception infectious-disease screening confirmation screen —
/// reached after scanning a registration's ticket QR (the exact same QR
/// the payment desk scans, see `qr_scan_screen.dart`'s
/// `QrScanMode.patientRegistrationScreening`). Records "سليم" (clear) or
/// "غير سليم" (flagged); until "سليم" is recorded, `PatientScreeningGate`
/// blocks payment and starting a task against this registration
/// server-side.
class PatientRegistrationScreeningScreen extends ConsumerStatefulWidget {
  const PatientRegistrationScreeningScreen({super.key, required this.initial});

  final RegistrationPaymentState initial;

  @override
  ConsumerState<PatientRegistrationScreeningScreen> createState() => _PatientRegistrationScreeningScreenState();
}

class _PatientRegistrationScreeningScreenState extends ConsumerState<PatientRegistrationScreeningScreen> {
  late RegistrationPaymentState _state;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
  }

  Future<void> _confirm(String status) async {
    setState(() => _submitting = true);
    try {
      final updated =
          await ref.read(patientRegistrationRepositoryProvider).confirmScreening(_state.registration.id, status);
      if (!mounted) return;
      setState(() => _state = updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status == 'clear' ? 'تم تسجيل المريض سليمًا.' : 'تم تسجيل نتيجة الفحص كغير سليمة.'),
      ));
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر تسجيل نتيجة الفحص.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _state.registration;

    return Scaffold(
      appBar: AppBar(title: const Text('فحص السلامة من الأمراض المعدية')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Directionality(textDirection: TextDirection.ltr, child: Text(r.phone)),
                  const SizedBox(height: 4),
                  Text('${r.serviceName ?? '—'} · ${r.registerDayName ?? '—'}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _StatusBanner(status: r.screeningStatus),
          const SizedBox(height: 24),
          Text('نتيجة فحص المختبر', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitting ? null : () => _confirm('clear'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('سليم'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitting ? null : () => _confirm('flagged'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('غير سليم'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      'clear' => (Colors.green, Icons.check_circle, 'الحالة الحالية: سليم'),
      'flagged' => (Colors.red, Icons.warning_amber, 'الحالة الحالية: غير سليم'),
      _ => (Colors.amber, Icons.hourglass_empty, 'الحالة الحالية: بانتظار الفحص'),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        border: Border.all(color: color.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: color.shade900, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
