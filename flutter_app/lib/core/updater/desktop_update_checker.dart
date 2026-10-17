import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

class DesktopUpdateInfo {
  const DesktopUpdateInfo({required this.version, required this.url, this.notes});

  factory DesktopUpdateInfo.fromJson(Map<String, dynamic> json) => DesktopUpdateInfo(
    version: json['version'] as String,
    url: json['url'] as String,
    notes: json['notes'] as String?,
  );

  final String version;
  final String url;
  final String? notes;
}

/// Checks the backend for a newer build of this platform and installs it.
///
/// Windows: downloads the Inno Setup installer and launches it in silent
/// mode before exiting this process — mirrors Telegram Desktop's flow.
/// Android (2026-10-17, by request): downloads the APK from the clinic
/// server and hands it to the system installer, which shows its usual
/// install confirmation — no store involved (see AppUpdatePlugin.kt).
/// iPhone builds can't be installed from inside an app, so iOS only learns
/// that a newer version is on the download page.
class DesktopUpdateChecker {
  const DesktopUpdateChecker._();

  static const _channel = MethodChannel('dental/app_update');

  /// Turned off from the profile page; on by default.
  static const autoCheckKey = 'app_update.auto_check';

  static bool get isSupported => !kIsWeb && (Platform.isWindows || Platform.isAndroid || Platform.isIOS);

  /// Whether this platform can install the update itself.
  static bool get canSelfInstall => Platform.isWindows || Platform.isAndroid;

  static String get _platform => Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'windows');

  static Future<bool> autoCheckEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(autoCheckKey) ?? true;

  static Future<void> setAutoCheck(bool enabled) async =>
      (await SharedPreferences.getInstance()).setBool(autoCheckKey, enabled);

  /// The newer build, or null when up to date. [throwOnError] lets a
  /// manual check say why it failed; the startup check stays silent.
  static Future<DesktopUpdateInfo?> checkForUpdate({bool throwOnError = false}) async {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final response = await dio.get<Map<String, dynamic>>(
        '${AppConfig.baseUrl}/app/version',
        queryParameters: {'platform': _platform},
      );
      final data = response.data;
      if (data == null || data['version'] == null || data['url'] == null) return null;

      final info = DesktopUpdateInfo.fromJson(data);
      final current = (await PackageInfo.fromPlatform()).version;
      return _isNewer(info.version, current) ? info : null;
    } catch (_) {
      // Offline, server unreachable, or a malformed response — never block
      // app startup over this; the user just doesn't get prompted this run.
      if (throwOnError) rethrow;
      return null;
    }
  }

  static bool _isNewer(String remote, String local) {
    final r = remote.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final l = local.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    for (var i = 0; i < r.length || i < l.length; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false;
  }

  /// Android: whether this app may hand an APK to the installer.
  static Future<bool> canInstallPackages() async =>
      !Platform.isAndroid || (await _channel.invokeMethod<bool>('canInstall') ?? false);

  /// Android: opens "Install unknown apps" for this app.
  static Future<void> openInstallSettings() => _channel.invokeMethod<void>('openInstallSettings');

  /// Downloads [info.url] and installs it. On Windows it launches Setup
  /// fully silently and exits so Setup can overwrite the running exe/DLLs;
  /// on Android it opens the system install confirmation.
  static Future<void> downloadAndInstall(DesktopUpdateInfo info, {void Function(double progress)? onProgress}) async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}${Platform.pathSeparator}updates');
    await dir.create(recursive: true);
    final name = Platform.isAndroid ? 'DentalClinicApp-${info.version}.apk' : 'DentalClinicSetup-${info.version}.exe';
    final path = '${dir.path}${Platform.pathSeparator}$name';

    await Dio().download(
      info.url,
      path,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );

    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('install', {'path': path});
      return;
    }

    // /VERYSILENT + /SUPPRESSMSGBOXES: no UI at all during install.
    // /NORESTART: never reboot the machine on our behalf. The installer's
    // own [Run] entry (see windows/installer/setup.iss) relaunches the app
    // once Setup finishes, matching Telegram's "update and reopen" feel.
    await Process.start(
      path,
      ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}
