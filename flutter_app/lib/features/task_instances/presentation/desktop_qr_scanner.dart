import 'dart:async';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/platform/qr_image_decoder.dart';

/// The QR scanner on the Windows app (2026-10-12, by request):
/// `mobile_scanner` has no Windows camera support, so this shows the
/// webcam through `camera_windows` and reads a still frame about twice a
/// second with a pure-Dart QR decoder. A USB/handheld QR reader works too:
/// it types the code into the field below and presses Enter, as those
/// readers do.
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

  @override
  void initState() {
    super.initState();
    _startCamera();
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
        Expanded(child: ColoredBox(color: Colors.black, child: camera)),
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
