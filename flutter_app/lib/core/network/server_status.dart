import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../config/server_settings_controller.dart';
import '../offline/connectivity_service.dart';

/// Whether the chosen server (cloud or the clinic's offline server)
/// answers right now — the green/red dot (2026-10-22, by request: "اضهار
/// حالة الاتصال بالسيرفر ... ومحاولة اعادة الاتصال").
enum ServerLink { checking, online, offline }

/// Why the last check failed, for the details sheet.
enum ServerDownReason { noNetwork, unreachable, database, server }

@immutable
class ServerStatus {
  const ServerStatus({
    this.link = ServerLink.checking,
    this.reason,
    this.statusCode,
    this.checking = false,
    this.failures = 0,
    this.checkedAt,
    this.lastOnlineAt,
  });

  final ServerLink link;
  final ServerDownReason? reason;
  final int? statusCode;

  /// A check is running now (the first one, a retry, or the button).
  final bool checking;

  /// Failed checks in a row — spaces out the automatic retries.
  final int failures;
  final DateTime? checkedAt;
  final DateTime? lastOnlineAt;

  bool get isOnline => link == ServerLink.online;
  bool get isOffline => link == ServerLink.offline;

  ServerStatus copyWith({bool? checking}) => ServerStatus(
    link: link,
    reason: reason,
    statusCode: statusCode,
    checking: checking ?? this.checking,
    failures: failures,
    checkedAt: checkedAt,
    lastOnlineAt: lastOnlineAt,
  );
}

/// Checks `GET /ping` (public; also touches the database) every
/// [onlineInterval] while connected, and retries faster after a failure
/// ([retryDelays]) so the app reconnects by itself as soon as the server
/// is back. Also re-checks at once when the device's network changes, when
/// the app comes back to the foreground, and when any API request fails to
/// connect ([report], wired in `apiClientProvider`). Restarts on a change
/// of server, since it watches [serverSettingsProvider].
final serverStatusProvider = NotifierProvider<ServerStatusController, ServerStatus>(ServerStatusController.new);

class ServerStatusController extends Notifier<ServerStatus> {
  static const onlineInterval = Duration(seconds: 30);
  static const retryDelays = [
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ];
  static const probeTimeout = Duration(seconds: 6);

  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  /// Bumped on every (re)build, so a check started for the previous server
  /// doesn't write its result over the new one's.
  int _generation = 0;

  @override
  ServerStatus build() {
    ref.watch(serverSettingsProvider);
    final generation = ++_generation;
    _disposed = false;
    _busy = false;
    final lifecycle = AppLifecycleListener(onResume: () => check());
    ref.listen(connectivityStreamProvider, (previous, next) {
      final connected = next.valueOrNull;
      if (connected == null || connected == previous?.valueOrNull) return;
      check();
    });
    ref.onDispose(() {
      if (generation == _generation) _disposed = true;
      _timer?.cancel();
      lifecycle.dispose();
    });
    Future.microtask(check);
    return const ServerStatus(checking: true);
  }

  /// Checks now (the "إعادة الاتصال" button, or any trigger above). A
  /// check already running is not started twice.
  Future<void> check() async {
    if (_busy || _disposed) return;
    _busy = true;
    _timer?.cancel();
    final generation = _generation;
    state = state.copyWith(checking: true);
    final previous = state;
    final result = await _probe();
    if (generation != _generation) return;
    _busy = false;
    if (_disposed) return;
    final now = DateTime.now();
    state = result.reason == null
        ? ServerStatus(link: ServerLink.online, checkedAt: now, lastOnlineAt: now)
        : ServerStatus(
            link: ServerLink.offline,
            reason: result.reason,
            statusCode: result.statusCode,
            failures: previous.failures + 1,
            checkedAt: now,
            lastOnlineAt: previous.lastOnlineAt,
          );
    _schedule();
  }

  /// From the API client: a request got an answer ([reachable]) or failed
  /// to connect. A success turns the dot green at once; a failure triggers
  /// a real check rather than turning red on one slow request.
  void report({required bool reachable}) {
    if (_disposed) return;
    if (!reachable) {
      if (!_busy) check();
      return;
    }
    if (state.isOnline || _busy) return;
    final now = DateTime.now();
    state = ServerStatus(link: ServerLink.online, checkedAt: now, lastOnlineAt: now);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final delay = state.isOnline ? onlineInterval : retryDelays[(state.failures - 1).clamp(0, retryDelays.length - 1)];
    _timer = Timer(delay, check);
  }

  Future<({ServerDownReason? reason, int? statusCode})> _probe() async {
    final connected = ref.read(connectivityStreamProvider).valueOrNull;
    // A plain Dio (not ApiClient): no token, no interceptors, short
    // timeouts. Clinic TLS/IP mapping still applies — every HttpClient
    // goes through ClinicNetwork's HttpOverrides.
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: probeTimeout,
        receiveTimeout: probeTimeout,
        headers: const {'Accept': 'application/json'},
        validateStatus: (_) => true,
      ),
    );
    try {
      final response = await dio.get<dynamic>('/ping', queryParameters: {'t': DateTime.now().millisecondsSinceEpoch});
      final code = response.statusCode ?? 0;
      // Any answer below 500 means the server is up — a 404 is an older
      // server without /ping, a 403 an offline server not activated yet.
      if (code < 500) return (reason: null, statusCode: code);
      final data = response.data;
      final dbDown = data is Map && data['database'] == false;
      return (reason: dbDown ? ServerDownReason.database : ServerDownReason.server, statusCode: code);
    } on DioException {
      return (reason: connected == false ? ServerDownReason.noNetwork : ServerDownReason.unreachable, statusCode: null);
    } catch (_) {
      return (reason: ServerDownReason.unreachable, statusCode: null);
    } finally {
      dio.close(force: true);
    }
  }
}
