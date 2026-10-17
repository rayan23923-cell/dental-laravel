import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../domain/clinic_settings_admin.dart';

final clinicSettingsAdminRepositoryProvider = Provider<ClinicSettingsAdminRepository>((ref) {
  return ClinicSettingsAdminRepository(ref.watch(apiClientProvider));
});

/// `/clinic-settings` — plain (non-`{data:}`-wrapped) JSON, matching
/// `Api\ClinicSettingController`'s own shape.
class ClinicSettingsAdminRepository {
  ClinicSettingsAdminRepository(this._client);
  final ApiClient _client;

  Future<ClinicSettingsAdmin> fetch() async {
    final data = await _client.getJson('/clinic-settings') as Map<String, dynamic>;
    return ClinicSettingsAdmin.fromJson(data);
  }

  /// `fields` are plain text/bool values; `clinicLogo`/`universityLogo`
  /// are optional picked images — always sent as multipart (with `_method:
  /// PUT` spoofing, see `ApiClient.postMultipart`) even when no file is
  /// attached this time, since a plain-fields form and a form-with-a-file
  /// hit the exact same endpoint and there's no reason to maintain two
  /// request-building paths for one screen.
  Future<ClinicSettingsAdmin> update(
    Map<String, dynamic> fields, {
    XFile? clinicLogo,
    XFile? universityLogo,
  }) async {
    final formData = FormData();
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) continue;
      // Laravel's `boolean` rule does a *strict* `in_array($value, [true,
      // false, 0, 1, '0', '1'], true)` — found live, via a real validation
      // error: the literal strings "true"/"false" (Dart's `bool.toString()`)
      // are not in that list at all, only "0"/"1" are. A multipart body has
      // no native boolean type, so every field is a string regardless —
      // this has to be the specific string Laravel's rule accepts.
      final stringValue = value is bool ? (value ? '1' : '0') : value.toString();
      formData.fields.add(MapEntry(entry.key, stringValue));
    }
    if (clinicLogo != null) {
      formData.files.add(MapEntry(
        'clinic_logo',
        MultipartFile.fromBytes(await clinicLogo.readAsBytes(), filename: clinicLogo.name),
      ));
    }
    if (universityLogo != null) {
      formData.files.add(MapEntry(
        'university_logo',
        MultipartFile.fromBytes(await universityLogo.readAsBytes(), filename: universityLogo.name),
      ));
    }

    final data = await _client.postMultipart('/clinic-settings', formData: formData, spoofedMethod: 'PUT')
        as Map<String, dynamic>;
    return ClinicSettingsAdmin.fromJson(data);
  }

  /// One test message through the *saved* SMTP settings; returns the
  /// server's message (the transport's own error text on failure comes
  /// back as an [ApiException]).
  Future<String> sendTestEmail(String to) async {
    final data = await _client.postJson('/clinic-settings/test-email', body: {'to': to}) as Map<String, dynamic>;
    return data['message'] as String? ?? '';
  }
}
