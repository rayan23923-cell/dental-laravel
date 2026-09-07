import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

/// Checks the backend for a newer Windows build and, if accepted, downloads
/// the Inno Setup installer and launches it in silent mode before exiting
/// this process — mirrors Telegram Desktop's self-update flow. Windows-only;
/// callers must guard for other platforms (see [DesktopUpdateGate]).
class DesktopUpdateChecker {
  const DesktopUpdateChecker._();

  static Future<DesktopUpdateInfo?> checkForUpdate() async {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final response = await dio.get<Map<String, dynamic>>('${AppConfig.baseUrl}/desktop/version');
      final data = response.data;
      if (data == null) return null;

      final info = DesktopUpdateInfo.fromJson(data);
      final current = (await PackageInfo.fromPlatform()).version;
      return _isNewer(info.version, current) ? info : null;
    } catch (_) {
      // Offline, server unreachable, or a malformed response — never block
      // app startup over this; the user just doesn't get prompted this run.
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

  /// Downloads [info.url] to a temp file, launches it fully silently, and
  /// exits this process immediately so Setup can overwrite the running
  /// exe/DLLs without a file-lock conflict. Does not return normally.
  static Future<void> downloadAndInstall(DesktopUpdateInfo info) async {
    final tempDir = await getTemporaryDirectory();
    final installerPath = '${tempDir.path}${Platform.pathSeparator}DentalClinicSetup-${info.version}.exe';

    final dio = Dio();
    await dio.download(info.url, installerPath);

    // /VERYSILENT + /SUPPRESSMSGBOXES: no UI at all during install.
    // /NORESTART: never reboot the machine on our behalf. The installer's
    // own [Run] entry (see windows/installer/setup.iss) relaunches the app
    // once Setup finishes, matching Telegram's "update and reopen" feel.
    await Process.start(
      installerPath,
      ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}
