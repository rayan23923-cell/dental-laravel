import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Where the Laravel API lives, per run target.
///
/// `--dart-define=API_BASE_URL=...` always wins (the one case that can't be
/// auto-detected: a physical device on the LAN needs the host machine's
/// IP). Without it, a platform-aware default covers the two zero-config
/// cases: the Android emulator's `10.0.2.2` loopback alias to the host, and
/// `localhost` for every other target (Windows/iOS simulator/web — all on
/// the same machine as XAMPP during development).
class AppConfig {
  const AppConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2/dental_laravel/public/api/v1';
    }
    return 'http://localhost/dental_laravel/public/api/v1';
  }

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
}
