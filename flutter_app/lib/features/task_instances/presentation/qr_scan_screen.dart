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
  // Case-sheet patient-identity autofill (2026-08-28) — same scan/resolve
  // as [taskPatientLink] (pops back with the resolved `PatientRegistration`
  // rather than navigating forward), a distinct mode so the call site
  // (`CaseSheetFormScreen`) and this screen's title read clearly for what
  // they're actually doing rather than reusing an unrelated-sounding name.
  caseSheetPatientAutofill,
  // The general "دفعة جديدة" form's patient-registration scan (2026-08-29)
  // — `payment_form_screen.dart` is staff-only (the `/records` hub), so
  // this reuses the same staff-gated `patient-registrations/scan` endpoint
  // [patientRegistrationPayment]/[taskPatientLink] already do, just named
  // for its own call site like [caseSheetPatientAutofill] is.
  paymentPatientLink,
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
  final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
        case QrScanMode.paymentPatientLink:
          final state = await ref.read(patientRegistrationRepositoryProvider).scan(raw);
          if (mounted) context.pop(state);
        case QrScanMode.caseSheetPatientAutofill:
          // Doctor-only route + PatientScreeningGate enforcement — see
          // PatientRegistrationRepository.scanForCaseSheet()'s doc comment.
          final state = await ref.read(patientRegistrationRepositoryProvider).scanForCaseSheet(raw);
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
        QrScanMode.caseSheetPatientAutofill => 'مسح رمز المريض',
        QrScanMode.paymentPatientLink => 'امسح رمز المريض',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          // Torch toggle — mirrors the web QrScanner.vue's existing
          // "تشغيل/إطفاء الفلاش" control (same feature, previously missing
          // here). ValueListenableBuilder keeps the icon in sync whether
          // the torch was toggled from here or turned off elsewhere (e.g.
          // the OS killing it when the app backgrounds).
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, child) {
              if (!state.isInitialized || state.torchState == TorchState.unavailable) {
                return const SizedBox.shrink();
              }
              return IconButton(
                onPressed: () => _controller.toggleTorch(),
                icon: Icon(state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off),
                tooltip: state.torchState == TorchState.on ? 'إطفاء الفلاش' : 'تشغيل الفلاش',
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Square aiming frame with corner brackets — purely visual (the
          // scanner itself reads the whole camera frame regardless), so a
          // user pointing at a QR code gets the same "aim here" cue this
          // app already gives on web (QrScanner.vue's green frame overlay).
          const IgnorePointer(child: CustomPaint(painter: _ScannerFramePainter())),
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

/// Draws a dimmed mask with a clear square cutout in the center, plus
/// bracket-style corners at that square — the standard QR-scanner "aim
/// here" affordance.
class _ScannerFramePainter extends CustomPainter {
  const _ScannerFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final frameSize = size.shortestSide * 0.65;
    final frameRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: frameSize,
      height: frameSize,
    );
    const cornerRadius = 16.0;
    final frameRRect = RRect.fromRectAndRadius(frameRect, const Radius.circular(cornerRadius));

    // Dimmed mask outside the frame — even-odd fill leaves the frame itself clear.
    final maskPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(frameRRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(maskPath, Paint()..color = Colors.black.withValues(alpha: 0.5));

    // Corner brackets.
    const bracketLength = 28.0;
    const strokeWidth = 4.0;
    final bracketPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    void drawCorner(Offset corner, Offset dx, Offset dy) {
      canvas.drawLine(corner, corner + dx * bracketLength, bracketPaint);
      canvas.drawLine(corner, corner + dy * bracketLength, bracketPaint);
    }

    drawCorner(frameRect.topLeft, const Offset(1, 0), const Offset(0, 1));
    drawCorner(frameRect.topRight, const Offset(-1, 0), const Offset(0, 1));
    drawCorner(frameRect.bottomLeft, const Offset(1, 0), const Offset(0, -1));
    drawCorner(frameRect.bottomRight, const Offset(-1, 0), const Offset(0, -1));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
