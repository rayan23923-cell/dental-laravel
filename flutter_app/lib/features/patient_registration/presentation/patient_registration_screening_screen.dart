import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
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
    final t = ref.read(translationsProvider);
    try {
      final updated =
          await ref.read(patientRegistrationRepositoryProvider).confirmScreening(_state.registration.id, status);
      if (!mounted) return;
      setState(() => _state = updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status == 'clear' ? t['screening.markedClear']! : t['screening.markedFlagged']!),
      ));
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['screening.recordFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _state.registration;
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['patientRegFlutter.screeningTooltip']!)),
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
          Text(t['screening.labResultHeading']!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitting ? null : () => _confirm('clear'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(t['patientRegFlutter.screeningClear']!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitting ? null : () => _confirm('flagged'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(t['patientRegFlutter.screeningFlagged']!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends ConsumerWidget {
  const _StatusBanner({required this.status});

  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final (color, icon, label) = switch (status) {
      'clear' => (Colors.green, Icons.check_circle, '${t['patientRegFlutter.currentStatusPrefix']} ${t['patientRegFlutter.screeningClear']}'),
      'flagged' => (Colors.red, Icons.warning_amber, '${t['patientRegFlutter.currentStatusPrefix']} ${t['patientRegFlutter.screeningFlagged']}'),
      _ => (Colors.amber, Icons.hourglass_empty, '${t['patientRegFlutter.currentStatusPrefix']} ${t['patientRegFlutter.screeningPending']}'),
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
