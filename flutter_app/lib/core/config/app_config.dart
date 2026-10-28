import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

import 'server_settings.dart';

/// Where the Laravel API lives, per run target.
///
/// Chosen at runtime since 2026-10-17: the user can switch to the offline
/// clinic server on the LAN ([server], set from `ServerSettingsController`
/// and at startup from `ServerBootstrap`). That choice wins; the cloud
/// server ([cloudBaseUrl]) is resolved as before:
///
/// `--dart-define=API_BASE_URL=...` always wins (the one case that can't be
/// auto-detected: a physical device on the LAN needs the host machine's
/// IP). Without it, a release build talks to the live server
/// ([productionBaseUrl]), and a debug build falls back to a platform-aware
/// default covering the two zero-config cases: the Android emulator's `10.0.2.2` loopback alias to the host, and
/// `localhost` for every other target (Windows/iOS simulator/web — all on
/// the same machine as XAMPP during development).
class AppConfig {
  const AppConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// The live server (Oracle VPS, 2026-10-11) — used by every release build
  /// that isn't given its own `--dart-define=API_BASE_URL`.
  static const String productionBaseUrl = 'https://dental.azoclinic.duckdns.org/api/v1';

  static ServerSettings _server = ServerSettings.cloud;

  /// The server chosen in the app (cloud by default).
  static ServerSettings get server => _server;

  /// Called at startup and whenever the user switches server — the API
  /// client is rebuilt right after (see `apiClientProvider`).
  static void useServer(ServerSettings settings) => _server = settings.normalized();

  /// The chosen server's identity, for per-server storage (login token,
  /// offline caches) — see [ServerSettings.id].
  static String get serverId => _server.id;

  /// Key prefix for data that belongs to one server. Empty for the cloud,
  /// so caches written before the server choice existed stay valid.
  static String get storageNamespace => _server.isClinic ? 'server[${_server.id}]::' : '';

  static String get baseUrl => _server.isClinic ? _server.apiBaseUrl : cloudBaseUrl;

  /// The cloud API, whatever server is chosen — app updates always come
  /// from here (`DesktopUpdateChecker`).
  static String get cloudBaseUrl {
    if (_override.isNotEmpty) return _override;
    if (kReleaseMode) return productionBaseUrl;
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2/dental_laravel/public/api/v1';
    }
    return 'http://localhost/dental_laravel/public/api/v1';
  }

  /// A build for Google Play / the App Store (`--dart-define=STORE_BUILD=true`,
  /// 2026-10-28): the stores deliver updates themselves and forbid an app
  /// installing its own, so the in-app updater is off (see
  /// `DesktopUpdateChecker.isSupported`). The /download and offline builds
  /// keep it.
  static const bool storeBuild = bool.fromEnvironment('STORE_BUILD');

  /// The cloud site's public pages (privacy policy, terms, support, account
  /// deletion) — the ones the store listings link to.
  static String sitePage(String path) => '${cloudBaseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '')}/$path';

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);

  /// Resolves a stored public-disk path (e.g. `endodontics-xrays/abc.jpg`,
  /// exactly what `Api\EndodonticsXrayController` hands back as `path`) to
  /// a viewable URL — [baseUrl] minus its `/api/v1` suffix, matching the
  /// web app's own `/storage/{path}` convention (see DoctorLayout.vue's
  /// profile photo preview).
  static String storageUrl(String path) => '${baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '')}/storage/$path';
}
