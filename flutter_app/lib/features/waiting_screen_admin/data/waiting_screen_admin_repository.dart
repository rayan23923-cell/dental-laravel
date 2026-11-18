import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final waitingScreenAdminRepositoryProvider = Provider<WaitingScreenAdminRepository>((ref) {
  return WaitingScreenAdminRepository(ref.watch(apiClientProvider));
});

/// `/waiting-screen-settings` (`Api\WaitingScreenSettingController`).
class WaitingScreenSettings {
  const WaitingScreenSettings({
    required this.groupId,
    required this.patientsPerPage,
    required this.rotationSeconds,
    this.labScope = 'today',
    this.voice = const VoiceSettings(),
  });

  factory WaitingScreenSettings.fromJson(Map<String, dynamic> json) => WaitingScreenSettings(
        groupId: json['group_id'] as int?,
        patientsPerPage: (json['patients_per_page'] as num?)?.toInt() ?? 8,
        rotationSeconds: (json['rotation_seconds'] as num?)?.toInt() ?? 10,
        labScope: json['lab_scope'] == 'all' ? 'all' : 'today',
        voice: VoiceSettings.fromJson(json),
      );

  /// Null shows every group.
  final int? groupId;
  final int patientsPerPage;
  final int rotationSeconds;

  /// 'today' (list empties at midnight) or 'all' pending (2026-11-03).
  final String labScope;

  /// Calling names by voice (2026-11-17); see `App\Support\VoiceCalls`.
  final VoiceSettings voice;
}

/// Calling names by voice on the waiting screen (2026-11-17, by request):
/// the server speaks «{before} {name}، {after}» and the screen plays it.
class VoiceSettings {
  const VoiceSettings({
    this.enabled = true,
    this.engine = 'piper',
    this.name = 'emirati',
    this.ready = true,
    this.readyBefore = '',
    this.readyAfter = '',
    this.waiting = false,
    this.waitingBefore = '',
    this.waitingAfter = '',
    this.repeat = 2,
    this.volume = 100,
    this.rate = 100,
    this.engines = const ['piper'],
    this.names = const [],
    this.installed = const [],
    this.downloadable = false,
    this.supported = false,
  });

  factory VoiceSettings.fromJson(Map<String, dynamic> json) => VoiceSettings(
        enabled: json['voice_enabled'] as bool? ?? true,
        engine: json['voice_engine'] as String? ?? 'piper',
        name: json['voice_name'] as String? ?? 'emirati',
        ready: json['voice_ready'] as bool? ?? true,
        readyBefore: json['voice_ready_before'] as String? ?? '',
        readyAfter: json['voice_ready_after'] as String? ?? '',
        waiting: json['voice_waiting'] as bool? ?? false,
        waitingBefore: json['voice_waiting_before'] as String? ?? '',
        waitingAfter: json['voice_waiting_after'] as String? ?? '',
        repeat: (json['voice_repeat'] as num?)?.toInt() ?? 2,
        volume: (json['voice_volume'] as num?)?.toInt() ?? 100,
        rate: (json['voice_rate'] as num?)?.toInt() ?? 100,
        engines: [for (final e in json['voice_engines'] as List<dynamic>? ?? const ['piper']) '$e'],
        names: [for (final e in json['voice_names'] as List<dynamic>? ?? const []) '$e'],
        installed: [for (final e in json['voice_installed'] as List<dynamic>? ?? const []) '$e'],
        downloadable: json['voice_downloadable'] as bool? ?? false,
        // Older servers do not send the voice settings at all.
        supported: json.containsKey('voice_enabled'),
      );

  final bool enabled;
  final String engine;
  final String name;
  final bool ready;
  final String readyBefore;
  final String readyAfter;
  final bool waiting;
  final String waitingBefore;
  final String waitingAfter;
  final int repeat;
  final int volume;
  final int rate;

  /// Engines this server runs, every voice offered, and those on this server.
  final List<String> engines;
  final List<String> names;
  final List<String> installed;

  /// True on the Windows server, which downloads voices when wanted.
  final bool downloadable;
  final bool supported;

  Map<String, dynamic> toJson() => {
        'voice_enabled': enabled,
        'voice_engine': engine,
        'voice_name': name,
        'voice_ready': ready,
        'voice_ready_before': readyBefore,
        'voice_ready_after': readyAfter,
        'voice_waiting': waiting,
        'voice_waiting_before': waitingBefore,
        'voice_waiting_after': waitingAfter,
        'voice_repeat': repeat,
        'voice_volume': volume,
        'voice_rate': rate,
      };
}

class WaitingScreenGroup {
  const WaitingScreenGroup({required this.id, required this.name, this.stageName});

  factory WaitingScreenGroup.fromJson(Map<String, dynamic> json) => WaitingScreenGroup(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        stageName: json['stage_name'] as String?,
      );

  final int id;
  final String name;
  final String? stageName;
}

/// A paired TV (2026-11-03, by request), controlled from the server.
class PairedScreen {
  const PairedScreen({
    required this.id,
    this.name,
    this.lastSeenAt,
    required this.online,
    required this.tvApp,
    this.version,
    this.openOnBoot,
    this.openOnWake,
    this.returnMinutes,
    this.overlay,
    required this.pending,
  });

  factory PairedScreen.fromJson(Map<String, dynamic> json) => PairedScreen(
        id: json['id'] as int,
        name: json['name'] as String?,
        lastSeenAt: DateTime.tryParse(json['last_seen_at'] as String? ?? '')?.toLocal(),
        online: json['online'] == true,
        tvApp: json['tv_app'] == true,
        version: json['version'] as String?,
        openOnBoot: json['open_on_boot'] as bool?,
        openOnWake: json['open_on_wake'] as bool?,
        returnMinutes: (json['return_minutes'] as num?)?.toInt(),
        overlay: json['overlay'] as bool?,
        pending: [for (final p in (json['pending'] as List<dynamic>? ?? const [])) '$p'],
      );

  final int id;
  final String? name;
  final DateTime? lastSeenAt;
  final bool online;
  final bool tvApp;
  final String? version;
  final bool? openOnBoot;
  final bool? openOnWake;
  final int? returnMinutes;
  final bool? overlay;
  final List<String> pending;
}

const pairedScreenReturnMinutes = [0, 1, 2, 5, 10, 30, 60];

class WaitingScreenSettingsPage {
  const WaitingScreenSettingsPage(this.settings, this.groups);
  final WaitingScreenSettings settings;
  final List<WaitingScreenGroup> groups;
}

/// The public waiting screen's settings, and pairing a TV by the 4-digit
/// code it shows (2026-10-17) — the web's `/waiting-screen-settings` and
/// `/waiting-screen/pair`. Pairing goes through the same two calls the
/// QR-scan flow uses: resolve the code to the pairing's token, then
/// confirm it with the chosen stage.
class WaitingScreenAdminRepository {
  WaitingScreenAdminRepository(this._client);
  final ApiClient _client;

  Future<WaitingScreenSettingsPage> fetch() async {
    final data = (await _client.getJson('/waiting-screen-settings') as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return WaitingScreenSettingsPage(
      WaitingScreenSettings.fromJson(data['settings'] as Map<String, dynamic>),
      [for (final g in data['groups'] as List<dynamic>) WaitingScreenGroup.fromJson(g as Map<String, dynamic>)],
    );
  }

  Future<WaitingScreenSettings> save({
    required int? groupId,
    required int patientsPerPage,
    required int rotationSeconds,
    required String labScope,
    Map<String, dynamic>? voice,
  }) async {
    final data = await _client.putJson('/waiting-screen-settings', body: {
      'group_id': groupId,
      'patients_per_page': patientsPerPage,
      'rotation_seconds': rotationSeconds,
      'lab_scope': labScope,
      ...?voice,
    }) as Map<String, dynamic>;
    return WaitingScreenSettings.fromJson((data['data'] as Map<String, dynamic>)['settings'] as Map<String, dynamic>);
  }

  /// «تجربة الصوت»: the WAV for a sample [name] with the form's wording.
  Future<List<int>> previewVoice({required String name, required String kind, required Map<String, dynamic> voice}) {
    return _client.postBytes('/waiting-screen-settings/voice-preview', body: {'name': name, 'kind': kind, ...voice});
  }

  /// The next piece of a voice the Windows server does not carry yet:
  /// `(received, total, done)`.
  Future<(int, int, bool)> downloadVoiceStep(String voice) async {
    final data = (await _client.postJson('/waiting-screen-settings/voices/$voice/download') as Map<String, dynamic>)['data']
        as Map<String, dynamic>;
    return ((data['received'] as num).toInt(), (data['total'] as num).toInt(), data['done'] == true);
  }

  Future<List<PairedScreen>> screens() async {
    final data = (await _client.getJson('/waiting-screen/screens') as Map<String, dynamic>)['data'] as List<dynamic>;
    return [for (final s in data) PairedScreen.fromJson(s as Map<String, dynamic>)];
  }

  /// Queues a command the screen picks up within seconds (reload,
  /// check_update, open_on_boot, open_on_wake, return_minutes).
  Future<void> command(int id, String type, [Object? value]) async {
    await _client.postJson('/waiting-screen/screens/$id/command', body: {'type': type, 'value': value});
  }

  Future<void> rename(int id, String name) async {
    await _client.patchJson('/waiting-screen/screens/$id', body: {'name': name});
  }

  Future<void> unpair(int id) async {
    await _client.deleteJson('/waiting-screen/screens/$id');
  }

  /// Activates the screen showing [code]; returns the stage name it now
  /// shows (null for all stages).
  Future<String?> pair({required String code, required int? stageId}) async {
    final resolved = await _client.postJson('/waiting-screen/pairings/resolve-code', body: {'code': code}) as Map<String, dynamic>;
    final token = (resolved['data'] as Map<String, dynamic>)['token'] as String;
    final confirmed = await _client.postJson('/waiting-screen/pairings/$token/confirm', body: {'stage_id': stageId})
        as Map<String, dynamic>;
    return (confirmed['data'] as Map<String, dynamic>?)?['stage_name'] as String?;
  }
}
