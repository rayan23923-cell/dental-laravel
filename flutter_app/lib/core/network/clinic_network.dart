import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import '../config/server_settings.dart';
import 'ca_certificate.dart';

/// How every `HttpClient` in the app reaches the offline clinic server
/// (2026-10-17): Dio (`ApiClient`, the updater), `Image.network` /
/// `NetworkImage` and `CachedNetworkImage` (via package:http) all create
/// their `HttpClient` through [HttpOverrides.global], which [install] sets.
///
/// Each client gets a connection factory that is consulted on every new
/// connection, so a change of server applies even to clients created
/// earlier (Flutter's `NetworkImage` keeps one for the whole run):
///
/// - TLS uses the system roots plus, while a clinic server is chosen, that
///   clinic's own root certificate (downloaded from `/ca.crt` and checked
///   by [CaCertificate]). Nothing else is accepted: no
///   `badCertificateCallback`, no "allow any certificate".
/// - When the clinic server has an IP set, connections to its name go to
///   that IP, while TLS still checks the certificate against the name —
///   the same name -> IP mapping the Windows LAN client does. Caddy's
///   certificate covers both the name and the IP (`https://$ServerName,
///   https://$ServerIp` in offline/windows/prepare.ps1).
///
/// No-op on the web, where the browser does TLS.
class ClinicNetwork {
  const ClinicNetwork._();

  static SecurityContext? _context;
  static String? _mappedHost;
  static String? _mappedIp;
  static String? _clinicHost;

  static void install() {
    if (kIsWeb) return;
    HttpOverrides.global = _ClinicHttpOverrides();
  }

  /// Applies the chosen server: trusts [caPem] (clinic only) and maps the
  /// clinic name to its IP. Throws [TlsException] if [caPem] can't be loaded.
  static void configure(ServerSettings settings, {String? caPem}) {
    if (kIsWeb) return;
    if (!settings.isClinic) {
      _context = null;
      _mappedHost = null;
      _mappedIp = null;
      _clinicHost = null;
      return;
    }
    _clinicHost = settings.host;
    _context = caPem == null ? null : contextTrusting(caPem);
    final hasIp = settings.ip.isNotEmpty && settings.ip != settings.host;
    _mappedHost = hasIp ? settings.host : null;
    _mappedIp = hasIp ? settings.ip : null;
  }

  /// System roots plus the clinic root.
  static SecurityContext contextTrusting(String caPem) =>
      SecurityContext(withTrustedRoots: true)..setTrustedCertificatesBytes(utf8.encode(caPem));

  /// The connection factory every app `HttpClient` uses. [explicitContext]
  /// is the context the client was created with, if any — kept as-is.
  static Future<ConnectionTask<Socket>> _connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
    SecurityContext? explicitContext,
  ) =>
      connectVia(
        uri,
        proxyHost,
        proxyPort,
        context: explicitContext ?? _context,
        mappedHost: _mappedHost,
        mappedIp: _mappedIp,
      );

  /// Opens the socket for [uri] the way `HttpClient` would by default,
  /// except that TLS uses [context] and [mappedHost] is reached at
  /// [mappedIp]. Through a proxy, the socket goes to the proxy and
  /// `HttpClient` itself tunnels and does TLS as usual.
  @visibleForTesting
  static Future<ConnectionTask<Socket>> connectVia(
    Uri uri,
    String? proxyHost,
    int? proxyPort, {
    SecurityContext? context,
    String? mappedHost,
    String? mappedIp,
  }) async {
    if (proxyHost != null && proxyPort != null) {
      return Socket.startConnect(proxyHost, proxyPort);
    }
    final host = uri.host;
    final port = uri.port;
    final ip = (mappedHost != null && mappedIp != null && host.toLowerCase() == mappedHost) ? mappedIp : null;
    if (!uri.isScheme('https')) {
      return Socket.startConnect(ip ?? host, port);
    }
    if (ip == null) {
      return SecureSocket.startConnect(host, port, context: context);
    }
    // TCP to the IP, then TLS for the name (SNI and certificate check).
    final tcp = await Socket.startConnect(ip, port);
    return ConnectionTask.fromSocket<Socket>(
      tcp.socket.then((s) => SecureSocket.secure(s, host: host, context: context)),
      tcp.cancel,
    );
  }

  /// Downloads `http://<server>:<httpPort>/ca.crt` and returns it as PEM
  /// if it's a self-signed CA. Throws [ClinicConnectionError] otherwise.
  static Future<String> downloadCa(ServerSettings settings, {Duration timeout = const Duration(seconds: 8)}) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = ((_) => 'DIRECT')
      ..connectionFactory = (uri, proxyHost, proxyPort) =>
          connectVia(uri, proxyHost, proxyPort, mappedHost: settings.host, mappedIp: settings.ip.isEmpty ? null : settings.ip);
    try {
      final request = await client.getUrl(Uri.parse(settings.caUrl)).timeout(timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(timeout);
      if (response.statusCode != 200) {
        throw ClinicConnectionError(ClinicConnectionFailure.notClinicServer, 'HTTP ${response.statusCode}');
      }
      final CaCertificate ca;
      try {
        ca = CaCertificate.parse(bytes);
      } on FormatException catch (e) {
        throw ClinicConnectionError(ClinicConnectionFailure.badCertificateFile, e.message);
      }
      try {
        contextTrusting(ca.pem);
      } on TlsException catch (e) {
        throw ClinicConnectionError(ClinicConnectionFailure.badCertificateFile, e.message);
      }
      return ca.pem;
    } on ClinicConnectionError {
      rethrow;
    } catch (e) {
      throw ClinicConnectionError.from(e);
    } finally {
      client.close(force: true);
    }
  }

  /// Calls the public `GET [apiBaseUrl]/branding` (HTTPS checked against
  /// the system roots plus [caPem]; [server] maps the clinic name to its
  /// IP). Returns the clinic name the server reports.
  static Future<String> checkApi(
    String apiBaseUrl, {
    ServerSettings? server,
    String? caPem,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final context = caPem == null ? SecurityContext(withTrustedRoots: true) : contextTrusting(caPem);
    final hasIp = server != null && server.ip.isNotEmpty && server.ip != server.host;
    final client = HttpClient()..connectionTimeout = timeout;
    // A LAN server is never behind the device's proxy.
    if (server != null) client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) => connectVia(
            uri,
            proxyHost,
            proxyPort,
            context: context,
            mappedHost: hasIp ? server.host : null,
            mappedIp: hasIp ? server.ip : null,
          );
    try {
      final request = await client.getUrl(Uri.parse('$apiBaseUrl/branding')).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode != 200) {
        throw ClinicConnectionError(ClinicConnectionFailure.notClinicServer, 'HTTP ${response.statusCode}');
      }
      final Object? json;
      try {
        json = jsonDecode(body);
      } catch (_) {
        throw const ClinicConnectionError(ClinicConnectionFailure.notClinicServer, 'not JSON');
      }
      if (json is! Map<String, dynamic>) {
        throw const ClinicConnectionError(ClinicConnectionFailure.notClinicServer, 'not JSON');
      }
      return json['clinic_name'] as String? ?? '';
    } on ClinicConnectionError {
      rethrow;
    } catch (e) {
      throw ClinicConnectionError.from(e);
    } finally {
      client.close(force: true);
    }
  }
}

class _ClinicHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // A LAN server is never reached through the device's proxy.
    client.findProxy = (uri) =>
        uri.host.toLowerCase() == ClinicNetwork._clinicHost ? 'DIRECT' : HttpClient.findProxyFromEnvironment(uri);
    client.connectionFactory = (uri, proxyHost, proxyPort) => ClinicNetwork._connect(uri, proxyHost, proxyPort, context);
    return client;
  }
}

enum ClinicConnectionFailure {
  /// The name doesn't resolve on this network (no DNS for clinic.lan).
  hostNotFound,

  /// Nothing answered: wrong address/port, other network, server off.
  unreachable,

  /// The TLS certificate wasn't trusted.
  certificate,

  /// `/ca.crt` wasn't a self-signed root certificate.
  badCertificateFile,

  /// Something answered, but not the clinic system's API.
  notClinicServer,
}

class ClinicConnectionError implements Exception {
  const ClinicConnectionError(this.failure, [this.detail = '']);

  factory ClinicConnectionError.from(Object e) {
    if (e is ClinicConnectionError) return e;
    if (e is HandshakeException || e is TlsException) {
      return ClinicConnectionError(ClinicConnectionFailure.certificate, '$e');
    }
    if (e is SocketException) {
      final m = e.message.toLowerCase();
      final os = (e.osError?.message ?? '').toLowerCase();
      if (m.contains('host lookup') || os.contains('no address') || os.contains('nodename') || os.contains('not known')) {
        return ClinicConnectionError(ClinicConnectionFailure.hostNotFound, '$e');
      }
      return ClinicConnectionError(ClinicConnectionFailure.unreachable, '$e');
    }
    if (e is TimeoutException) return ClinicConnectionError(ClinicConnectionFailure.unreachable, '$e');
    if (e is HttpException) return ClinicConnectionError(ClinicConnectionFailure.notClinicServer, '$e');
    return ClinicConnectionError(ClinicConnectionFailure.unreachable, '$e');
  }

  final ClinicConnectionFailure failure;
  final String detail;

  @override
  String toString() => 'ClinicConnectionError(${failure.name}: $detail)';
}
