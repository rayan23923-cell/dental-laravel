import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Which server this install talks to (2026-10-17): the hosted cloud
/// server, or the offline edition running on a clinic PC on the LAN
/// (`offline/README.md`). Same fields and defaults as the Windows LAN
/// client's `ClientSettings` (offline/windows/client/DentalClinicClient.cs).
enum ServerKind { cloud, clinic }

class ServerSettings {
  const ServerSettings({
    this.kind = ServerKind.cloud,
    this.host = defaultHost,
    this.ip = '',
    this.httpsPort = 443,
    this.httpPort = 80,
  });

  static const cloud = ServerSettings();
  static const defaultHost = 'clinic.lan';

  /// The server a fresh install starts on, before the user chooses one:
  /// the cloud, unless built with `--dart-define=DEFAULT_SERVER=clinic`
  /// (the builds shipped inside the offline package), optionally with
  /// `--dart-define=DEFAULT_SERVER_HOST=...` (default clinic.lan).
  static ServerSettings get compiledDefault => defaultFor(
        const String.fromEnvironment('DEFAULT_SERVER'),
        const String.fromEnvironment('DEFAULT_SERVER_HOST'),
      );

  static ServerSettings defaultFor(String defaultServer, String defaultHost) {
    if (defaultServer.trim().toLowerCase() != ServerKind.clinic.name) return cloud;
    return ServerSettings(kind: ServerKind.clinic, host: defaultHost).normalized();
  }

  final ServerKind kind;

  /// The clinic server's name (`SERVER_NAME` in its config.txt) or an IP.
  final String host;

  /// Optional IP of the clinic server. When set, connections to [host] go
  /// to this address (name -> IP, like the Windows client), so the app
  /// works even where the name doesn't resolve.
  final String ip;
  final int httpsPort;
  final int httpPort;

  bool get isClinic => kind == ServerKind.clinic;

  /// Identity of the server for everything that belongs to one server:
  /// the login token and the offline caches. The IP is not part of it —
  /// it's just how to reach the same server.
  String get id => isClinic ? 'clinic:$host:$httpsPort' : 'cloud';

  String get origin => 'https://${_hostForUrl(host)}${httpsPort == 443 ? '' : ':$httpsPort'}';

  String get apiBaseUrl => '$origin/api/v1';

  /// Where the clinic's root certificate is served over plain http (see
  /// `(lanfiles)` in offline/windows/prepare.ps1). Goes to the IP when one
  /// is set, so it comes down even before the name works on this device.
  String get caUrl => '$httpBase/ca.crt';

  /// Plain-http base of the clinic server (IP when set, like the Windows
  /// client's `HttpBase`): the certificate and the app builds it serves.
  String get httpBase => 'http://${_hostForUrl(ip.isNotEmpty ? ip : host)}${httpPort == 80 ? '' : ':$httpPort'}';

  /// The app builds shipped inside the offline package (`/apps/`), listed
  /// in the same shape as the cloud's public/downloads/releases.json.
  String get releasesUrl => '$httpBase/apps/releases.json';

  static String _hostForUrl(String h) => h.contains(':') ? '[$h]' : h;

  /// "https://clinic.lan:443/x" -> "clinic.lan" (same as the Windows
  /// client's `CleanHost`).
  static String cleanHost(String? s) {
    var v = (s ?? '').trim();
    final scheme = v.indexOf('://');
    if (scheme >= 0) v = v.substring(scheme + 3);
    final end = v.indexOf(RegExp(r'[/:?#\s]'));
    if (end >= 0) v = v.substring(0, end);
    return v.toLowerCase();
  }

  static bool isIpv4(String s) {
    final parts = s.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) => RegExp(r'^\d{1,3}$').hasMatch(p) && int.parse(p) <= 255);
  }

  static bool validPort(int? p) => p != null && p > 0 && p <= 65535;

  ServerSettings normalized() {
    final h = cleanHost(host);
    return ServerSettings(
      kind: kind,
      host: h.isEmpty ? defaultHost : h,
      ip: cleanHost(ip),
      httpsPort: validPort(httpsPort) ? httpsPort : 443,
      httpPort: validPort(httpPort) ? httpPort : 80,
    );
  }

  ServerSettings copyWith({ServerKind? kind, String? host, String? ip, int? httpsPort, int? httpPort}) => ServerSettings(
        kind: kind ?? this.kind,
        host: host ?? this.host,
        ip: ip ?? this.ip,
        httpsPort: httpsPort ?? this.httpsPort,
        httpPort: httpPort ?? this.httpPort,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'host': host,
        'ip': ip,
        'https_port': httpsPort,
        'http_port': httpPort,
      };

  factory ServerSettings.fromJson(Map<String, dynamic> json) => ServerSettings(
        kind: json['kind'] == ServerKind.clinic.name ? ServerKind.clinic : ServerKind.cloud,
        host: json['host'] as String? ?? defaultHost,
        ip: json['ip'] as String? ?? '',
        httpsPort: (json['https_port'] as num?)?.toInt() ?? 443,
        httpPort: (json['http_port'] as num?)?.toInt() ?? 80,
      ).normalized();

  @override
  bool operator ==(Object other) =>
      other is ServerSettings &&
      other.kind == kind &&
      other.host == host &&
      other.ip == ip &&
      other.httpsPort == httpsPort &&
      other.httpPort == httpPort;

  @override
  int get hashCode => Object.hash(kind, host, ip, httpsPort, httpPort);

  @override
  String toString() => 'ServerSettings(${toJson()})';
}

/// The chosen server and the clinic's root certificate, in
/// SharedPreferences. The certificate is public (anyone on the LAN can
/// download it), so it needs no secure storage.
class ServerSettingsStore {
  const ServerSettingsStore();

  static const _kSettings = 'server.settings';
  static const _kCaPem = 'server.clinic_ca_pem';
  static const _kCaFor = 'server.clinic_ca_for';

  /// The saved choice, or [fallback] (default
  /// [ServerSettings.compiledDefault]) when the user hasn't chosen yet.
  Future<ServerSettings> load({ServerSettings? fallback}) async {
    final initial = fallback ?? ServerSettings.compiledDefault;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSettings);
      if (raw == null) return initial;
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? ServerSettings.fromJson(json) : initial;
    } catch (_) {
      return initial;
    }
  }

  Future<void> save(ServerSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSettings, jsonEncode(settings.normalized().toJson()));
  }

  /// The stored root certificate (PEM) of the clinic server [serverId],
  /// or null when none was stored for that server.
  Future<String?> loadCa(String serverId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kCaFor) != serverId) return null;
      return prefs.getString(_kCaPem);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCa(String serverId, String pem) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCaPem, pem);
    await prefs.setString(_kCaFor, serverId);
  }
}
