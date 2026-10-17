import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../network/clinic_network.dart';
import 'app_config.dart';
import 'server_settings.dart';

/// Loads the chosen server before the app starts (from `main()`), so the
/// very first request already goes to the right place and trusts the
/// right certificate.
class ServerBootstrap {
  const ServerBootstrap._();

  static Future<void> init({ServerSettingsStore store = const ServerSettingsStore()}) async {
    ClinicNetwork.install();
    // The web build is served by its own server; the browser does TLS.
    if (kIsWeb) return;
    final settings = await store.load();
    AppConfig.useServer(settings);
    if (!settings.isClinic) return;
    var pem = await store.loadCa(settings.id);
    if (pem == null) {
      // Saved without the certificate (e.g. set up away from the clinic
      // network): try once more, briefly — the app still opens if not.
      try {
        pem = await ClinicNetwork.downloadCa(settings, timeout: const Duration(seconds: 3));
        await store.saveCa(settings.id, pem);
      } catch (_) {}
    }
    try {
      ClinicNetwork.configure(settings, caPem: pem);
    } catch (_) {
      ClinicNetwork.configure(settings);
    }
  }
}

/// The server this app talks to. Changing it ([apply]) logs out of the
/// old server — tokens belong to the server that issued them — and, since
/// `apiClientProvider` watches this, rebuilds the API client (and with it
/// every repository and the auth state).
final serverSettingsProvider = NotifierProvider<ServerSettingsController, ServerSettings>(ServerSettingsController.new);

class ServerSettingsController extends Notifier<ServerSettings> {
  static const store = ServerSettingsStore();

  @override
  ServerSettings build() => AppConfig.server;

  /// [caPem] is the clinic's checked root certificate (from
  /// `ClinicNetwork.downloadCa`), when one was obtained.
  Future<void> apply(ServerSettings next, {String? caPem}) async {
    next = next.normalized();
    final previous = state;
    if (next == previous && caPem == null) return;
    final sameServer = previous.id == next.id;
    if (!sameServer) {
      // Best-effort: revokes the token on the old server and clears it.
      try {
        await ref.read(authControllerProvider.notifier).logout();
      } catch (_) {}
    }
    await store.save(next);
    if (next.isClinic && caPem != null) await store.saveCa(next.id, caPem);
    final pem = next.isClinic ? (caPem ?? await store.loadCa(next.id)) : null;
    AppConfig.useServer(next);
    ClinicNetwork.configure(next, caPem: pem);
    state = next;
  }
}
