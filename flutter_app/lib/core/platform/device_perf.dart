import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Weak-device mode (2026-11-03, by request: the app was very slow on the
/// clinic's Android POS terminals, e.g. the Q2 on Android 8.1, above all
/// when opening the camera).
///
/// Read once before `runApp` (DevicePerfPlugin.kt). When [lowEnd] is true
/// the app drops the effects a weak GPU/CPU struggles with: the glass
/// blur behind the footer and "+" button, the long splash animation, the
/// zoom page transition, and full-size decoding of small avatars.
class DevicePerf {
  DevicePerf._();

  static const _channel = MethodChannel('dental/device_perf');

  static bool _lowEnd = false;

  /// True on Android devices with little RAM, few cores or Android < 9.
  static bool get lowEnd => _lowEnd;

  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final info = await _channel
          .invokeMapMethod<String, Object?>('info')
          .timeout(const Duration(milliseconds: 800));
      _lowEnd = info?['lowEnd'] == true;
    } catch (_) {
      // Unknown: keep the full effects.
    }
  }

  /// Decodes a small avatar at its shown size instead of the full photo
  /// (a camera photo is ~12 MP; a footer avatar is 28 px).
  static ImageProvider avatar(String url, {int size = 160}) =>
      ResizeImage(NetworkImage(url), width: size);
}
