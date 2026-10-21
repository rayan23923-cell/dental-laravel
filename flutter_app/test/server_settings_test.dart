// Server choice (cloud / offline clinic server on the LAN), its
// persistence, per-server login and caches, and the clinic certificate
// (2026-10-17).

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_app/core/config/app_config.dart';
import 'package:dental_clinic_app/core/config/server_settings.dart';
import 'package:dental_clinic_app/core/network/ca_certificate.dart';
import 'package:dental_clinic_app/core/network/clinic_network.dart';
import 'package:dental_clinic_app/core/offline/local_json_store.dart';
import 'package:dental_clinic_app/core/storage/token_storage.dart';
import 'package:dental_clinic_app/core/updater/desktop_update_checker.dart';
import 'package:dental_clinic_app/features/auth/domain/account_type.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<int> fixture(String name) => File('test/fixtures/clinic_tls/$name').readAsBytesSync();

const clinic = ServerSettings(kind: ServerKind.clinic);

void main() {
  tearDown(() => AppConfig.useServer(ServerSettings.cloud));

  group('URLs', () {
    test('clinic defaults', () {
      expect(clinic.origin, 'https://clinic.lan');
      expect(clinic.apiBaseUrl, 'https://clinic.lan/api/v1');
      expect(clinic.caUrl, 'http://clinic.lan/ca.crt');
      expect(clinic.releasesUrl, 'http://clinic.lan/apps/releases.json');
      expect(clinic.id, 'clinic:clinic.lan:443');
    });

    test('ports and IP', () {
      final s = clinic.copyWith(ip: '192.168.68.10', httpsPort: 8443, httpPort: 8080);
      expect(s.apiBaseUrl, 'https://clinic.lan:8443/api/v1');
      // Plain http goes to the IP, so the certificate comes down even
      // where the name doesn't resolve.
      expect(s.caUrl, 'http://192.168.68.10:8080/ca.crt');
      expect(s.httpBase, 'http://192.168.68.10:8080');
      // The IP isn't part of the server's identity.
      expect(s.id, 'clinic:clinic.lan:8443');
    });

    test('an IP as the address', () {
      final s = clinic.copyWith(host: '192.168.1.5');
      expect(s.apiBaseUrl, 'https://192.168.1.5/api/v1');
      expect(s.caUrl, 'http://192.168.1.5/ca.crt');
    });

    test('cleaning what the user typed', () {
      expect(ServerSettings.cleanHost(' HTTPS://Clinic.LAN:443/x '), 'clinic.lan');
      expect(clinic.copyWith(host: '  ', httpsPort: 0, httpPort: 70000).normalized(),
          const ServerSettings(kind: ServerKind.clinic));
      expect(ServerSettings.isIpv4('192.168.1.10'), isTrue);
      expect(ServerSettings.isIpv4('192.168.1.256'), isFalse);
      expect(ServerSettings.isIpv4('clinic.lan'), isFalse);
    });

    test('JSON round trip', () {
      final s = clinic.copyWith(ip: '10.0.0.2', httpsPort: 444, httpPort: 8080);
      expect(ServerSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>), s);
    });

    test('compile-time default server', () {
      expect(ServerSettings.defaultFor('', ''), ServerSettings.cloud);
      expect(ServerSettings.defaultFor('cloud', 'x'), ServerSettings.cloud);
      expect(ServerSettings.defaultFor('clinic', ''), clinic);
      expect(ServerSettings.defaultFor('CLINIC', 'Office.Lan'), clinic.copyWith(host: 'office.lan'));
      // This test build has no DEFAULT_SERVER define.
      expect(ServerSettings.compiledDefault, ServerSettings.cloud);
    });

    test('AppConfig follows the chosen server', () {
      expect(AppConfig.baseUrl, AppConfig.cloudBaseUrl);
      expect(AppConfig.storageNamespace, '');
      expect(AppConfig.serverId, 'cloud');

      AppConfig.useServer(clinic.copyWith(httpsPort: 8443));
      expect(AppConfig.baseUrl, 'https://clinic.lan:8443/api/v1');
      expect(AppConfig.storageUrl('xrays/a.jpg'), 'https://clinic.lan:8443/storage/xrays/a.jpg');
      expect(AppConfig.storageNamespace, 'server[clinic:clinic.lan:8443]::');
      // App updates of cloud mode still come from the cloud.
      expect(AppConfig.cloudBaseUrl, isNot(contains('clinic.lan')));
    });
  });

  group('persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('nothing chosen yet -> the default', () async {
      const store = ServerSettingsStore();
      expect(await store.load(), ServerSettings.cloud);
      expect(await store.load(fallback: clinic), clinic);
    });

    test('the choice survives a restart', () async {
      const store = ServerSettingsStore();
      final s = clinic.copyWith(ip: '192.168.68.10', httpPort: 8080);
      await store.save(s);
      expect(await const ServerSettingsStore().load(fallback: ServerSettings.cloud), s);
      await store.save(ServerSettings.cloud);
      expect(await store.load(fallback: clinic), ServerSettings.cloud);
    });

    test('the certificate belongs to one server', () async {
      const store = ServerSettingsStore();
      await store.saveCa(clinic.id, 'PEM');
      expect(await store.loadCa(clinic.id), 'PEM');
      expect(await store.loadCa('clinic:other.lan:443'), isNull);
    });

    test('login token is per server', () async {
      FlutterSecureStorage.setMockInitialValues({});
      var current = 'cloud';
      final storage = TokenStorage(currentServerId: () => current);

      await storage.save(token: 'cloud-token', accountType: AccountType.staff);
      expect(await storage.readToken(), 'cloud-token');
      expect(await TokenStorage(currentServerId: () => current).readToken(), 'cloud-token');

      current = clinic.id;
      expect(await storage.readToken(), isNull);
      expect(await storage.readAccountType(), isNull);

      await storage.save(token: 'clinic-token', accountType: AccountType.doctor);
      expect(await storage.readToken(), 'clinic-token');
      expect(await storage.readAccountType(), AccountType.doctor);

      await storage.clear();
      expect(await storage.readToken(), isNull);
    });

    test('a token saved before servers existed belongs to the cloud', () async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'old', 'account_type': 'staff'});
      expect(await TokenStorage(currentServerId: () => 'cloud').readToken(), 'old');
      expect(await TokenStorage(currentServerId: () => clinic.id).readToken(), isNull);
    });

    test('offline caches are per server', () async {
      SharedPreferences.setMockInitialValues({'offline_case_sheet_pending::x::1': '{"a":1}'});
      const cloudStore = LocalJsonStore(namespace: _cloudNs);
      const clinicStore = LocalJsonStore(namespace: _clinicNs);

      expect(await cloudStore.getJson('offline_case_sheet_pending::x::1'), {'a': 1});
      expect(await clinicStore.getJson('offline_case_sheet_pending::x::1'), isNull);

      await clinicStore.putJson('offline_case_sheet_pending::y::2', {'b': 2});
      expect(await clinicStore.keysWithPrefix('offline_case_sheet_pending::'), ['offline_case_sheet_pending::y::2']);
      expect(await cloudStore.keysWithPrefix('offline_case_sheet_pending::'), ['offline_case_sheet_pending::x::1']);
      expect(await clinicStore.getJson('offline_case_sheet_pending::y::2'), {'b': 2});
    });
  });

  group('clinic certificate file', () {
    test('accepts the self-signed root, PEM or DER', () {
      final pem = CaCertificate.parse(fixture('root.crt'));
      final der = CaCertificate.parse(fixture('root.der'));
      expect(der.pem, pem.pem);
      expect(pem.pem, startsWith('-----BEGIN CERTIFICATE-----\n'));
      // Loads into a SecurityContext.
      ClinicNetwork.contextTrusting(pem.pem);
    });

    test('rejects anything that is not a self-signed CA', () {
      for (final name in ['leaf.crt', 'inter.crt', 'selfsigned_leaf.crt', 'server_key.pem']) {
        expect(() => CaCertificate.parse(fixture(name)), throwsFormatException, reason: name);
      }
      expect(() => CaCertificate.parse(utf8.encode('<html>login</html>')), throwsFormatException);
      expect(() => CaCertificate.parse([0x30, 0x82, 0xFF]), throwsFormatException);
    });
  });

  test('clinic releases.json', () {
    final releases = {
      'windows': {'version': '1.1.120', 'url': '/apps/DentalClinicSetup-1.1.120.exe'},
      'android': {'version': '1.1.120', 'url': '/apps/DentalClinicApp-1.1.120.apk', 'notes': 'x'},
    };
    final info = DesktopUpdateChecker.clinicReleaseFor(releases, 'android', 'http://192.168.68.10:8080')!;
    expect(info.version, '1.1.120');
    expect(info.url, 'http://192.168.68.10:8080/apps/DentalClinicApp-1.1.120.apk');
    expect(info.notes, 'x');
    expect(DesktopUpdateChecker.clinicReleaseFor(releases, 'ios', 'http://clinic.lan'), isNull);
    expect(DesktopUpdateChecker.clinicReleaseFor(null, 'android', 'http://clinic.lan'), isNull);
    expect(
      DesktopUpdateChecker.clinicReleaseFor({
        'android': {'version': '2.0.0', 'url': 'https://elsewhere.example/a.apk'},
      }, 'android', 'http://clinic.lan')!.url,
      'https://elsewhere.example/a.apk',
    );
  });

  test('update source: offline server address and order', () {
    const cloud = ServerSettings.cloud;
    final signedIn = const ServerSettings(kind: ServerKind.clinic, host: 'srv.lan', httpPort: 8080).normalized();
    expect(DesktopUpdateChecker.clinicServerFor('', cloud).releasesUrl, 'http://clinic.lan/apps/releases.json');
    expect(DesktopUpdateChecker.clinicServerFor('', signedIn).releasesUrl, 'http://srv.lan:8080/apps/releases.json');
    expect(
      DesktopUpdateChecker.clinicServerFor('192.168.1.10:8080', signedIn).releasesUrl,
      'http://192.168.1.10:8080/apps/releases.json',
    );
    expect(DesktopUpdateChecker.clinicServerFor('http://Clinic.LAN/apps', cloud).releasesUrl, 'http://clinic.lan/apps/releases.json');

    expect(DesktopUpdateChecker.sourcesToTry(UpdateSource.internet, onClinic: true), [UpdateSource.internet]);
    expect(DesktopUpdateChecker.sourcesToTry(UpdateSource.clinic, onClinic: false), [UpdateSource.clinic]);
    expect(DesktopUpdateChecker.sourcesToTry(UpdateSource.auto, onClinic: true), [UpdateSource.clinic, UpdateSource.internet]);
    expect(DesktopUpdateChecker.sourcesToTry(UpdateSource.auto, onClinic: false), [UpdateSource.internet, UpdateSource.clinic]);
  });

  group('connecting to a clinic server', () {
    late HttpServer https;
    late HttpServer http;
    late String rootPem;

    setUpAll(() async {
      final serverContext = SecurityContext()
        ..useCertificateChainBytes(fixture('server_chain.pem'))
        ..usePrivateKeyBytes(fixture('server_key.pem'));
      https = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      https.listen((req) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(req.uri.path == '/api/v1/branding' ? '{"clinic_name":"Test Clinic"}' : '{}');
        req.response.close();
      });
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      http.listen((req) {
        if (req.uri.path == '/ca.crt') {
          req.response.add(fixture('root.crt'));
        } else if (req.uri.path == '/leaf.crt') {
          req.response.add(fixture('leaf.crt'));
        } else {
          req.response.statusCode = 404;
        }
        req.response.close();
      });
      rootPem = utf8.decode(fixture('root.crt'));
    });

    tearDownAll(() async {
      await https.close(force: true);
      await http.close(force: true);
    });

    // clinic.lan doesn't resolve here, like a phone whose router has no
    // DNS for it: the IP setting maps it to the server.
    ServerSettings server() => clinic.copyWith(ip: '127.0.0.1', httpsPort: https.port, httpPort: http.port);

    test('downloads and checks the certificate, then reaches the API', () async {
      final pem = await ClinicNetwork.downloadCa(server());
      expect(CaCertificate.parse(utf8.encode(pem)).der, CaCertificate.parse(fixture('root.crt')).der);
      expect(await ClinicNetwork.checkApi(server().apiBaseUrl, server: server(), caPem: pem), 'Test Clinic');
    });

    test('by IP directly (the certificate covers it)', () async {
      final s = clinic.copyWith(host: '127.0.0.1', httpsPort: https.port, httpPort: http.port);
      expect(await ClinicNetwork.checkApi(s.apiBaseUrl, server: s, caPem: rootPem), 'Test Clinic');
    });

    test('never trusts the server without the clinic certificate', () async {
      Future<ClinicConnectionFailure> failure(String? pem) async {
        try {
          await ClinicNetwork.checkApi(server().apiBaseUrl, server: server(), caPem: pem);
        } on ClinicConnectionError catch (e) {
          return e.failure;
        }
        fail('connected without a trusted certificate');
      }

      expect(await failure(null), ClinicConnectionFailure.certificate);
      expect(await failure(utf8.decode(fixture('other_root.crt'))), ClinicConnectionFailure.certificate);
    });

    test('refuses a ca.crt that is not a root', () async {
      final s = server();
      final bad = ServerSettings(kind: ServerKind.clinic, ip: '127.0.0.1', httpPort: s.httpPort);
      // Same server, but pretend /ca.crt is the leaf: served at /leaf.crt.
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('${bad.httpBase}/leaf.crt'));
      final body = await (await req.close()).fold<List<int>>([], (a, b) => a..addAll(b));
      client.close();
      expect(() => CaCertificate.parse(body), throwsFormatException);
    });

    test('a name that does not resolve and no IP', () async {
      final s = ServerSettings(kind: ServerKind.clinic, host: 'no-such-host.invalid', httpPort: http.port);
      try {
        await ClinicNetwork.downloadCa(s, timeout: const Duration(seconds: 5));
        fail('downloaded from a host that does not exist');
      } on ClinicConnectionError catch (e) {
        expect(e.failure, anyOf(ClinicConnectionFailure.hostNotFound, ClinicConnectionFailure.unreachable));
      }
    });

    test('every HttpClient in the app follows the chosen server', () async {
      ClinicNetwork.install();
      addTearDown(() {
        ClinicNetwork.configure(ServerSettings.cloud);
        HttpOverrides.global = null;
      });

      Future<String> get() async {
        final client = HttpClient(); // what Dio, Image.network and package:http create
        try {
          final req = await client.getUrl(Uri.parse('${server().apiBaseUrl}/branding'));
          return await (await req.close()).transform(utf8.decoder).join();
        } finally {
          client.close(force: true);
        }
      }

      ClinicNetwork.configure(server(), caPem: rootPem);
      expect(await get(), contains('Test Clinic'));

      // Back to the cloud: the clinic certificate and the mapping are gone.
      ClinicNetwork.configure(ServerSettings.cloud);
      await expectLater(get(), throwsA(anything));
    });
  });

  test('an IP is pinned only for a clinic name with none set', () async {
    const named = ServerSettings(kind: ServerKind.clinic, host: 'clinic.lan', ip: '192.168.1.5');
    expect(await named.withPinnedIp(), named);
    const byIp = ServerSettings(kind: ServerKind.clinic, host: '192.168.1.5');
    expect(await byIp.withPinnedIp(), byIp);
    expect(await ServerSettings.cloud.withPinnedIp(), ServerSettings.cloud);
    // localhost resolves only to loopback, which is never kept.
    const local = ServerSettings(kind: ServerKind.clinic, host: 'localhost');
    expect((await local.withPinnedIp()).ip, '');
  });
}

String _cloudNs() => '';
String _clinicNs() => 'server[${clinic.id}]::';
