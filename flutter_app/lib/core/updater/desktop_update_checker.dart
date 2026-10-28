import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../config/server_settings.dart';

/// Where app updates come from (2026-10-21, by request): the internet
/// (the cloud's /download), the clinic's offline server on the LAN
/// (`/apps/`), or [auto] — the chosen server's source first, then the
/// other one when that can't be reached.
enum UpdateSource { auto, internet, clinic }

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
///
/// With the clinic's offline server chosen, the builds come from that
/// server's /apps/releases.json instead of the cloud (2026-10-17). Since
/// 2026-10-21 the user can pick the source on the profile page instead
/// ([UpdateSource]), e.g. update a cloud install from the clinic's LAN.
class DesktopUpdateChecker {
  const DesktopUpdateChecker._();

  static const _channel = MethodChannel('dental/app_update');

  /// Turned off from the profile page; on by default.
  static const autoCheckKey = 'app_update.auto_check';

  // Never in a store build: the store updates it (AppConfig.storeBuild).
  static bool get isSupported =>
      !kIsWeb && !AppConfig.storeBuild && (Platform.isWindows || Platform.isAndroid || Platform.isIOS);

  /// Whether this platform can install the update itself.
  static bool get canSelfInstall => Platform.isWindows || Platform.isAndroid;

  static String get _platform => Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'windows');

  static Future<bool> autoCheckEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(autoCheckKey) ?? true;

  static Future<void> setAutoCheck(bool enabled) async =>
      (await SharedPreferences.getInstance()).setBool(autoCheckKey, enabled);

  static const sourceKey = 'app_update.source';
  static const clinicHostKey = 'app_update.clinic_host';

  static Future<UpdateSource> source() async {
    final name = (await SharedPreferences.getInstance()).getString(sourceKey);
    return UpdateSource.values.where((s) => s.name == name).firstOrNull ?? UpdateSource.auto;
  }

  static Future<void> setSource(UpdateSource source) async =>
      (await SharedPreferences.getInstance()).setString(sourceKey, source.name);

  /// The offline server to update from, as typed on the profile page
  /// ("clinic.lan", "192.168.1.10" or "192.168.1.10:8080"). Empty: the
  /// chosen clinic server, else [ServerSettings.defaultHost].
  static Future<String> clinicHost() async =>
      (await SharedPreferences.getInstance()).getString(clinicHostKey) ?? '';

  static Future<void> setClinicHost(String host) async =>
      (await SharedPreferences.getInstance()).setString(clinicHostKey, host.trim());

  /// The offline server the builds come from: [typed] ("host" or
  /// "host:httpPort") when given, else the clinic server the app is
  /// signed in to, else clinic.lan on port 80.
  static ServerSettings clinicServerFor(String typed, ServerSettings current) {
    var v = typed.trim();
    final scheme = v.indexOf('://');
    if (scheme >= 0) v = v.substring(scheme + 3);
    v = v.split(RegExp(r'[/?#\s]')).first;
    if (v.isEmpty) return current.isClinic ? current : const ServerSettings(kind: ServerKind.clinic);
    var port = 80;
    final colon = v.lastIndexOf(':');
    if (colon > 0 && !v.substring(0, colon).contains(':')) {
      port = int.tryParse(v.substring(colon + 1)) ?? 80;
      v = v.substring(0, colon);
    }
    final host = ServerSettings.cleanHost(v);
    return ServerSettings(
      kind: ServerKind.clinic,
      host: host,
      ip: ServerSettings.isIpv4(host) ? host : '',
      httpPort: port,
    ).normalized();
  }

  /// The sources to try, in order, for [source].
  static List<UpdateSource> sourcesToTry(UpdateSource source, {required bool onClinic}) => switch (source) {
        UpdateSource.internet => [UpdateSource.internet],
        UpdateSource.clinic => [UpdateSource.clinic],
        UpdateSource.auto => onClinic
            ? [UpdateSource.clinic, UpdateSource.internet]
            : [UpdateSource.internet, UpdateSource.clinic],
      };

  /// The newer build, or null when up to date. [throwOnError] lets a
  /// manual check say why it failed; the startup check stays silent.
  /// [source] defaults to the one saved on the profile page.
  static Future<DesktopUpdateInfo?> checkForUpdate({bool throwOnError = false, UpdateSource? source}) async {
    final server = AppConfig.server;
    final order = sourcesToTry(source ?? await DesktopUpdateChecker.source(), onClinic: server.isClinic);
    final clinic = order.contains(UpdateSource.clinic) ? clinicServerFor(await clinicHost(), server) : null;
    Object? lastError;
    for (final from in order) {
      try {
        final info = await _latestFrom(from, clinic);
        if (info == null) return null;
        final current = (await PackageInfo.fromPlatform()).version;
        return _isNewer(info.version, current) ? info : null;
      } catch (e) {
        // Unreachable — try the next source, if any.
        lastError = e;
      }
    }
    // Offline, server unreachable, or a malformed response — never block
    // app startup over this; the user just doesn't get prompted this run.
    if (throwOnError && lastError != null) throw lastError;
    return null;
  }

  static Future<DesktopUpdateInfo?> _latestFrom(UpdateSource from, ServerSettings? clinic) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );
    if (from == UpdateSource.clinic) {
      // Offline package (2026-10-17): the clinic server ships the app
      // builds itself, at http://<server>/apps/ — no internet needed.
      final response = await dio.get<String>(
        clinic!.releasesUrl,
        options: Options(responseType: ResponseType.plain),
      );
      return clinicReleaseFor(jsonDecode(response.data ?? 'null'), _platform, clinic.httpBase);
    }
    final response = await dio.get<Map<String, dynamic>>(
      '${AppConfig.cloudBaseUrl}/app/version',
      queryParameters: {'platform': _platform},
    );
    final data = response.data;
    return (data == null || data['version'] == null || data['url'] == null) ? null : DesktopUpdateInfo.fromJson(data);
  }

  /// This platform's entry of the clinic server's apps/releases.json
  /// (same shape as the cloud's public/downloads/releases.json:
  /// {"windows": {"version", "url"}, "android": {...}, "ios": {...}}),
  /// with its relative url ("/apps/DentalClinicApp-1.1.120.apk") resolved
  /// against the clinic server's plain-http base [httpBase].
  static DesktopUpdateInfo? clinicReleaseFor(Object? releases, String platform, String httpBase) {
    if (releases is! Map) return null;
    final entry = releases[platform];
    if (entry is! Map) return null;
    final version = entry['version'];
    final url = entry['url'];
    if (version is! String || url is! String || version.isEmpty || url.isEmpty) return null;
    final notes = entry['notes'];
    return DesktopUpdateInfo(
      version: version,
      url: Uri.parse('$httpBase/').resolve(url).toString(),
      notes: notes is String ? notes : null,
    );
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
