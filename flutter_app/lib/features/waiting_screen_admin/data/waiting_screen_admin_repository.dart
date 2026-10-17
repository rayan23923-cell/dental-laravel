import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final waitingScreenAdminRepositoryProvider = Provider<WaitingScreenAdminRepository>((ref) {
  return WaitingScreenAdminRepository(ref.watch(apiClientProvider));
});

/// `/waiting-screen-settings` (`Api\WaitingScreenSettingController`).
class WaitingScreenSettings {
  const WaitingScreenSettings({required this.groupId, required this.patientsPerPage, required this.rotationSeconds});

  factory WaitingScreenSettings.fromJson(Map<String, dynamic> json) => WaitingScreenSettings(
        groupId: json['group_id'] as int?,
        patientsPerPage: (json['patients_per_page'] as num?)?.toInt() ?? 8,
        rotationSeconds: (json['rotation_seconds'] as num?)?.toInt() ?? 10,
      );

  /// Null shows every group.
  final int? groupId;
  final int patientsPerPage;
  final int rotationSeconds;
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

  Future<WaitingScreenSettings> save({required int? groupId, required int patientsPerPage, required int rotationSeconds}) async {
    final data = await _client.putJson('/waiting-screen-settings', body: {
      'group_id': groupId,
      'patients_per_page': patientsPerPage,
      'rotation_seconds': rotationSeconds,
    }) as Map<String, dynamic>;
    return WaitingScreenSettings.fromJson((data['data'] as Map<String, dynamic>)['settings'] as Map<String, dynamic>);
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
