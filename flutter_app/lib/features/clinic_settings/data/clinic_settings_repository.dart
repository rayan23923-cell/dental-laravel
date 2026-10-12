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

  /// Saves only the lab fee and result validity (2026-10-12). `PUT
  /// /clinic-settings` updates just the keys it is sent but requires
  /// `clinic_name`, so the current name is fetched and resent unchanged.
  Future<ClinicSettings> updateLab({double? labFee, required int labValidityDays}) async {
    final current = await fetch();
    final data = await _client.putJson('/clinic-settings', body: {
      'clinic_name': current.clinicName,
      'lab_fee': labFee,
      'lab_validity_days': labValidityDays,
    }) as Map<String, dynamic>;
    return ClinicSettings.fromJson(data);
  }
}
