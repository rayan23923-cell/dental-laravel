import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/network/api_exception.dart';
import '../../patient_registration/data/patient_registration_repository.dart';
import '../data/task_instance_repository.dart';
import 'task_instances_providers.dart';

/// Which QR flow this screen is resolving a scan for — see `_onDetect`.
/// Independent flows share one scanner screen instead of duplicating the
/// `MobileScanner` boilerplate per feature.
enum QrScanMode {
  taskInstance,
  patientRegistrationPayment,
  // Added for the infectious-disease screening feature (2026-08-26) — both
  // resolve the exact same ticket QR as [patientRegistrationPayment], just
  // routed to a different next step.
  patientRegistrationScreening,
  taskPatientLink,
}

/// Scans a QR code and resolves it against the flow-appropriate endpoint:
///
/// - [QrScanMode.taskInstance]: `{"type":"task_instance","id":N}`, see
///   `Api\TaskInstanceQrController` — resolved via
///   `POST /task-instances/scan`, then opens that instance's detail
///   screen (same round-trip the web app's QR check-in performs).
/// - [QrScanMode.patientRegistrationPayment]: `{"type":"patient_registration","id":N}`,
///   see `Api\PatientRegistrationQrController` — resolved via
///   `POST /patient-registrations/scan`, then opens the payment screen
///   with the returned registration + payment state.
/// - [QrScanMode.patientRegistrationScreening]: same payload/endpoint as
///   above, but opens the lab-confirmation screen instead of payment.
/// - [QrScanMode.taskPatientLink]: same payload/endpoint again, but pops
///   back to the caller with the resolved state instead of navigating
///   forward — used by `task_progress_screen.dart` to identify which
///   patient a "بدء المهمة" call is for.
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key, this.mode = QrScanMode.taskInstance});

  final QrScanMode mode;

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  bool _handled = false;
  String? _error;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    setState(() {
      _handled = true;
      _error = null;
    });

    try {
      switch (widget.mode) {
        case QrScanMode.taskInstance:
          final instance = await ref.read(taskInstanceRepositoryProvider).scan(raw);
          invalidateTaskInstance(ref, instance.id);
          if (mounted) context.pushReplacement('/tasks/${instance.id}');
        case QrScanMode.patientRegistrationPayment:
          final state = await ref.read(patientRegistrationRepositoryProvider).scan(raw);
          if (mounted) context.pushReplacement('/records/patient-registrations/payment', extra: state);
        case QrScanMode.patientRegistrationScreening:
          final state = await ref.read(patientRegistrationRepositoryProvider).scan(raw);
          if (mounted) context.pushReplacement('/records/patient-registrations/screening', extra: state);
        case QrScanMode.taskPatientLink:
          final state = await ref.read(patientRegistrationRepositoryProvider).scan(raw);
          if (mounted) context.pop(state);
      }
    } catch (e) {
      setState(() {
        _handled = false;
        _error = e is ApiException ? e.userMessage : 'رمز غير معروف.';
      });
    }
  }

  String get _title => switch (widget.mode) {
        QrScanMode.taskInstance => 'مسح رمز QR',
        QrScanMode.patientRegistrationPayment => 'مسح رمز الدفع',
        QrScanMode.patientRegistrationScreening => 'مسح رمز الفحص',
        QrScanMode.taskPatientLink => 'امسح رمز المريض',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(onPressed: () => setState(() => _error = null), child: const Text('حسنًا')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
