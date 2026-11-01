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

  /// Saves only the lab fee and result validity (2026-10-12), through the
  /// registration settings' own endpoint (2026-10-24) so whoever holds that
  /// permission (the accountant) can save it without the clinic settings.
  Future<ClinicSettings> updateLab({double? labFee, required int labValidityDays, double? labStudentDiscountPercent}) async {
    final data = await _client.putJson('/register-settings/lab', body: {
      'lab_fee': labFee,
      'lab_validity_days': labValidityDays,
      if (labStudentDiscountPercent != null) 'lab_student_discount_percent': labStudentDiscountPercent,
    }) as Map<String, dynamic>;
    return ClinicSettings.fromJson(data);
  }

  /// Care cards on/off from the registration settings (2026-11-01).
  Future<ClinicSettings> updateSupportCodes(bool enabled) async {
    final data = await _client.putJson('/register-settings/support-codes', body: {'support_codes_enabled': enabled})
        as Map<String, dynamic>;
    return ClinicSettings.fromJson(data);
  }
}
