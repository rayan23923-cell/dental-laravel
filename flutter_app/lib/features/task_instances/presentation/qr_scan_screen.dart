import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_state.dart';
import '../../patient_registration/data/patient_registration_repository.dart';
import '../../task_progress_admin/data/task_progress_repository.dart';
import '../data/task_instance_repository.dart';
import '../../../core/platform/platform_support.dart';
import 'desktop_qr_scanner.dart';
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
  const QrScanScreen({super.key, this.mode = QrScanMode.taskInstance, this.typeCode = false});

  final QrScanMode mode;

  /// Opened from "إدخال الرمز" (2026-10-30): the case code field right away.
  final bool typeCode;

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  bool _handled = false;
  String? _error;
  // Windows has no mobile_scanner camera (2026-10-12): DesktopQrScanner
  // is used there instead, so this controller is only made elsewhere.
  final MobileScannerController? _controller =
      isWindowsDesktop ? null : MobileScannerController(facing: _lastFacing);

  // The camera last switched to (2026-10-14), so the next scan opens on it.
  static CameraFacing _lastFacing = CameraFacing.back;

  Future<void> _switchCamera() async {
    await _controller?.switchCamera();
    _lastFacing = _lastFacing == CameraFacing.back ? CameraFacing.front : CameraFacing.back;
  }

  @override
  void initState() {
    super.initState();
    if (widget.typeCode) WidgetsBinding.instance.addPostFrameCallback((_) => _typeCode());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Staff who follow task progress: a case's QR or typed code opens the
  /// case with its task progress actions (2026-10-30, by request) instead
  /// of the plain detail screen.
  bool get _isSupervisor {
    final authState = ref.read(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    return account is StaffAccount && account.can('task_progress', 'view');
  }

  /// The digits under the case's QR on the student's account (2026-10-30,
  /// by request), for when the camera can't read the code.
  Future<void> _typeCode() async {
    final t = ref.read(translationsProvider);
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) {
        void submit() => Navigator.of(ctx).pop(controller.text.trim());
        return AlertDialog(
          title: Text(t['caseCode.enterTitle']!),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 4, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: t['caseCode.inputLabel'],
                  hintText: '000 000',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => submit(),
              ),
              const SizedBox(height: 8),
              Text(t['caseCode.inputHint']!, style: Theme.of(ctx).textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(t['taskProgressAdmin.cancel']!)),
            FilledButton(onPressed: submit, child: Text(t['caseCode.open']!)),
          ],
        );
      },
    );
    if (code == null || !mounted) return;
    if (code.isEmpty) {
      setState(() => _error = t['caseCode.invalid']);
      return;
    }
    await _handle(code);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    await _handle(raw);
  }

  /// `{"type":"doctor","id":N}`, printed on the doctor's ID card.
  int? _doctorIdOf(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['type'] == 'doctor' && decoded['id'] is int) return decoded['id'] as int;
    } catch (_) {}
    return null;
  }

  Future<void> _handle(String raw) async {
    if (_handled) return;

    setState(() {
      _handled = true;
      _error = null;
    });

    try {
      switch (widget.mode) {
        case QrScanMode.taskInstance:
          // A doctor's ID card QR (2026-10-14) opens that doctor's task
          // progress, as the web's task-progress scanner does.
          final doctorId = _doctorIdOf(raw);
          if (doctorId != null) {
            if (mounted) context.pushReplacement('/admin/doctors/$doctorId/progress');
            return;
          }
          if (_isSupervisor) {
            final result = await ref.read(taskProgressRepositoryProvider).lookup(raw);
            if (!mounted) return;
            if (result.isDoctorCard) {
              context.pushReplacement('/admin/doctors/${result.doctor.id}/progress');
            } else {
              context.pushReplacement('/admin/case-lookup', extra: result);
            }
            return;
          }
          final instance = await ref.read(taskInstanceRepositoryProvider).scan(raw);
          invalidateTaskInstance(ref, instance.id);
          if (mounted) context.pushReplacement('/tasks/${instance.id}');
        case QrScanMode.patientRegistrationPayment:
          final state = await ref.read(patientRegistrationRepositoryProvider).scan(raw);
          if (mounted) context.pushReplacement('/records/patient-registrations/payment', extra: state);
        case QrScanMode.patientRegistrationScreening:
          // Lab-gated scan (2026-10-17), so the `lab` role can scan too.
          final state = await ref.read(patientRegistrationRepositoryProvider).labScan(raw);
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
      final t = ref.read(translationsProvider);
      setState(() {
        _handled = false;
        _error = e is ApiException ? e.userMessage : t['qrScan.unknownCode']!;
      });
    }
  }

  String _title(Map<String, String> t) => switch (widget.mode) {
        QrScanMode.taskInstance => t['qrScan.titleTaskInstance']!,
        QrScanMode.patientRegistrationPayment => t['qrScan.titlePayment']!,
        QrScanMode.patientRegistrationScreening => t['qrScan.titleScreening']!,
        QrScanMode.taskPatientLink => t['qrScan.titlePatient']!,
        QrScanMode.caseSheetPatientAutofill => t['qrScan.titlePatientAutofill']!,
        QrScanMode.paymentPatientLink => t['qrScan.titlePatient']!,
      };

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(t)),
        actions: [
          if (_controller != null)
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
                tooltip: state.torchState == TorchState.on ? t['qrScan.torchOff']! : t['qrScan.torchOn']!,
              );
            },
          ),
          // Rear ↔ front camera, like the web scanner's switch button.
          if (_controller != null)
            IconButton(
              onPressed: _switchCamera,
              icon: const Icon(Icons.cameraswitch_outlined),
              tooltip: t['qrScan.switchCamera']!,
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_controller == null)
            DesktopQrScanner(onCode: _handle, paused: _handled)
          else ...[
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Square aiming frame with corner brackets — purely visual (the
          // scanner itself reads the whole camera frame regardless), so a
          // user pointing at a QR code gets the same "aim here" cue this
          // app already gives on web (QrScanner.vue's green frame overlay).
          const IgnorePointer(child: CustomPaint(painter: _ScannerFramePainter())),
          ],
          if (widget.mode == QrScanMode.taskInstance)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: FilledButton.tonalIcon(
                  onPressed: _handled ? null : _typeCode,
                  icon: const Icon(Icons.keyboard_outlined),
                  label: Text(t['caseCode.enterButton']!),
                ),
              ),
            ),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: widget.mode == QrScanMode.taskInstance ? 84 : 24,
              child: MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(onPressed: () => setState(() => _error = null), child: Text(t['common.ok']!)),
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
