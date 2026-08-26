import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/clinic_settings.dart';

final clinicSettingsRepositoryProvider = Provider<ClinicSettingsRepository>((ref) {
  return ClinicSettingsRepository(ref.watch(apiClientProvider));
});

class ClinicSettingsRepository {
  ClinicSettingsRepository(this._client);
  final ApiClient _client;

  Future<ClinicSettings> fetch() async {
    final data = await _client.getJson('/clinic-settings') as Map<String, dynamic>;
    return ClinicSettings.fromJson(data);
  }
}
