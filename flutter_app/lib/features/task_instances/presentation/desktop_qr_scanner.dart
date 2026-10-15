import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/platform/qr_image_decoder.dart';
import '../../../core/network/api_exception.dart';
import '../../phone_scanner/phone_scanner_pairing.dart';

/// The QR scanner on the Windows app (2026-10-12, by request):
/// `mobile_scanner` has no Windows camera support, so this shows the
/// webcam through `camera_windows` and reads a still frame about twice a
/// second with a pure-Dart QR decoder. A USB/handheld QR reader works too:
/// it types the code into the field below and presses Enter, as those
/// readers do. A phone can also be linked as the scanner (2026-10-12):
/// its codes arrive here while this scanner is open.
class DesktopQrScanner extends ConsumerStatefulWidget {
  const DesktopQrScanner({super.key, required this.onCode, this.paused = false});

  final ValueChanged<String> onCode;

  /// True while the caller is resolving a code, so frames aren't read.
  final bool paused;

  @override
  ConsumerState<DesktopQrScanner> createState() => _DesktopQrScannerState();
}

class _DesktopQrScannerState extends ConsumerState<DesktopQrScanner> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  int? _cameraId;
  String? _cameraError;
  bool _noCamera = false;
  bool _reading = false;
  Timer? _timer;

  // The linked phone, if any, and its poll timer.
  final _phone = ValueNotifier<PhoneScannerSession?>(null);
  Timer? _phoneTimer;
  bool _polling = false;
  bool _skipBacklog = true;
  BuildContext? _dialogContext;

  @override
  void initState() {
    super.initState();
    _startCamera();
    _restorePhone();
  }

  Future<void> _restorePhone() async {
    final session = await ref.read(phoneScannerPairingProvider).saved();
    if (!mounted || session == null) return;
    _phone.value = session;
    _startPhonePolling();
  }

  void _startPhonePolling() {
    _phoneTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _pollPhone());
    _pollPhone();
  }

  Future<void> _pollPhone() async {
    final session = _phone.value;
    if (session == null || _polling) return;
    _polling = true;
    try {
      final batch = await ref.read(phoneScannerPairingProvider).poll(session);
      if (!mounted) return;
      if (batch == null) {
        _stopPhonePolling();
        _phone.value = null;
        return;
      }
      if (batch.phoneJoined != session.phoneJoined) _phone.value = session.withJoined(batch.phoneJoined);
      // Codes the phone sent while no scanner was open are dropped, so an
      // old scan never acts on whatever this scanner was opened for.
      final skip = _skipBacklog;
      _skipBacklog = false;
      if (skip || widget.paused || batch.payloads.isEmpty) return;
      // A code while the pairing dialog is up: close it first, so the
      // caller acting on the code doesn't pop the dialog instead.
      final dialog = _dialogContext;
      if (dialog != null && dialog.mounted) {
        Navigator.of(dialog).pop();
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
      }
      for (final code in batch.payloads) {
        widget.onCode(code);
      }
    } catch (_) {
      // Offline for a moment: the next tick tries again.
    } finally {
      _polling = false;
    }
  }

  void _stopPhonePolling() {
    _phoneTimer?.cancel();
    _phoneTimer = null;
  }

  Future<void> _showPhoneDialog() async {
    final t = ref.read(translationsProvider);
    final pairing = ref.read(phoneScannerPairingProvider);
    if (_phone.value == null) {
      try {
        _phone.value = await pairing.open();
        _skipBacklog = false;
        _startPhonePolling();
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
        }
        return;
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => ValueListenableBuilder<PhoneScannerSession?>(
        valueListenable: _phone,
        builder: (context, session, _) {
          _dialogContext = context;
          return AlertDialog(
            title: Text(t['phoneScanner.title']!, textAlign: TextAlign.center),
            content: session == null
                ? Text(t['phoneScanner.ended']!)
                : SizedBox(
                    width: 320,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t['phoneScanner.howTo']!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Image.memory(Uint8List.fromList(session.qrPng), width: 220, height: 220),
                        const SizedBox(height: 8),
                        Text(t['phoneScanner.orCode']!, style: Theme.of(context).textTheme.bodySmall),
                        SelectableText(
                          session.code,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 8,
                            fontFamily: 'monospace',
                          ),
                        ),
                        SelectableText(
                          session.enterUrl,
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: session.phoneJoined ? Colors.green.shade50 : Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                session.phoneJoined ? Icons.check_circle : Icons.hourglass_empty,
                                color: session.phoneJoined ? Colors.green.shade700 : Colors.amber.shade800,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  session.phoneJoined ? t['phoneScanner.connected']! : t['phoneScanner.waiting']!,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
            actions: [
              if (session != null)
                TextButton(
                  onPressed: () async {
                    _stopPhonePolling();
                    _phone.value = null;
                    await pairing.close(session);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: Text(t['phoneScanner.end']!, style: const TextStyle(color: Colors.red)),
                ),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(t['common.close']!)),
            ],
          );
        },
      ),
    );
    _dialogContext = null;
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await CameraPlatform.instance.availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _noCamera = true);
        return;
      }
      final id = await CameraPlatform.instance.createCameraWithSettings(
        cameras.first,
        const MediaSettings(resolutionPreset: ResolutionPreset.high, enableAudio: false),
      );
      await CameraPlatform.instance.initializeCamera(id);
      if (!mounted) {
        await CameraPlatform.instance.dispose(id);
        return;
      }
      setState(() => _cameraId = id);
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _readFrame());
    } catch (e) {
      if (mounted) setState(() => _cameraError = '$e');
    }
  }

  Future<void> _readFrame() async {
    final id = _cameraId;
    if (id == null || _reading || widget.paused) return;
    _reading = true;
    try {
      final file = await CameraPlatform.instance.takePicture(id);
      final bytes = await file.readAsBytes();
      unawaited(File(file.path).delete().catchError((_) => File(file.path)));
      final text = await compute(decodeQrFromImageBytes, bytes);
      if (text != null && mounted && !widget.paused) widget.onCode(text);
    } catch (_) {
      // A dropped frame is fine; the next tick tries again.
    } finally {
      _reading = false;
    }
  }

  void _submitTyped(String value) {
    final text = value.trim();
    _field.clear();
    _focus.requestFocus();
    if (text.isNotEmpty) widget.onCode(text);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopPhonePolling();
    _phone.dispose();
    final id = _cameraId;
    if (id != null) CameraPlatform.instance.dispose(id);
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final id = _cameraId;

    final Widget camera;
    if (id != null) {
      camera = Center(child: CameraPlatform.instance.buildPreview(id));
    } else if (_noCamera || _cameraError != null) {
      camera = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _noCamera ? t['qrScan.noCamera']! : '${t['qrScan.cameraFailed']!}\n$_cameraError',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } else {
      camera = const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: ColoredBox(color: Colors.black, child: camera),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: ValueListenableBuilder<PhoneScannerSession?>(
            valueListenable: _phone,
            builder: (context, session, _) => SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showPhoneDialog,
                icon: Icon(
                  Icons.phonelink_ring,
                  color: session == null ? null : (session.phoneJoined ? Colors.green : Colors.amber.shade800),
                ),
                label: Text(
                  session == null
                      ? t['phoneScanner.button']!
                      : (session.phoneJoined ? t['phoneScanner.connectedShort']! : t['phoneScanner.waitingShort']!),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _field,
            focusNode: _focus,
            autofocus: true,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.qr_code_scanner),
              labelText: t['qrScan.usbReaderLabel']!,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: _submitTyped,
          ),
        ),
      ],
    );
  }
}
