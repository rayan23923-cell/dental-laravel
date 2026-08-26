import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../auth/domain/account_type.dart';
import '../../auth/domain/auth_account.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(apiClientProvider));
});

/// `PUT /me` / `PUT /me/password` — mirrors `Api\ProfileController`, which
/// dual-dispatches on account type server-side the same way `GET /me`
/// already does. This repository just needs to know which JSON shape to
/// parse the response back into, same as `AuthRepository.fetchMe`.
class ProfileRepository {
  ProfileRepository(this._client);
  final ApiClient _client;

  Future<AuthAccount> update({
    required AccountType accountType,
    required Map<String, dynamic> fields,
    XFile? photo,
  }) async {
    final formData = FormData();
    for (final entry in fields.entries) {
      if (entry.value == null) continue;
      formData.fields.add(MapEntry(entry.key, entry.value.toString()));
    }
    if (photo != null) {
      formData.files.add(MapEntry(
        'profile_image',
        MultipartFile.fromBytes(await photo.readAsBytes(), filename: photo.name),
      ));
    }

    final data = await _client.postMultipart('/me', formData: formData, spoofedMethod: 'PUT') as Map<String, dynamic>;

    return switch (accountType) {
      AccountType.staff => StaffAccount.fromJson(data),
      AccountType.doctor => DoctorAccount.fromJson(data),
    };
  }

  Future<void> updatePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _client.putJson('/me/password', body: {
      'old_password': oldPassword,
      'new_password': newPassword,
      'new_password_confirmation': newPassword,
    });
  }
}
