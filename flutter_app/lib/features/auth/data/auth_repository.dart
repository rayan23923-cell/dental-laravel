import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/account_type.dart';
import '../domain/auth_account.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

/// `device_name` sent with every login — no `device_info_plus`/
/// `package_info_plus` in this slice's dependency set, so this identifies
/// the platform, not the specific install. Good enough for the API's
/// `required|string` validation; a richer per-install name is a natural
/// later follow-up, not silently added here.
String _deviceName() {
  if (kIsWeb) return 'web • dental_clinic_app';
  return '${Platform.operatingSystem} • dental_clinic_app';
}

class AuthRepository {
  AuthRepository(this._client);
  final ApiClient _client;

  /// One field, either the account's email or its username — mirrors
  /// `App\Http\Requests\Auth\LoginRequest`'s web form exactly. The server
  /// tries a staff match first, then a doctor match (see
  /// `Api\AuthController::login()`), and its `account_type` in the
  /// response says which one actually matched, so the caller doesn't have
  /// to guess or ask upfront which kind of account this is.
  Future<(String token, AccountType type, AuthAccount account)> login({
    required String identifier,
    required String password,
  }) async {
    final data = await _client.postJson('/login', body: {
      'login': identifier,
      'password': password,
      'device_name': _deviceName(),
    }) as Map<String, dynamic>;

    final token = data['token'] as String;
    final type = data['account_type'] == 'doctor' ? AccountType.doctor : AccountType.staff;
    final account = type == AccountType.doctor
        ? DoctorAccount.fromJson(data['doctor'] as Map<String, dynamic>)
        : StaffAccount.fromJson(data['user'] as Map<String, dynamic>);

    return (token, type, account);
  }

  /// "نسيت كلمة المرور؟" — unified across both account types, same
  /// reasoning as [login]. See `Api\PasswordResetController` docblock:
  /// always succeeds with a neutral message regardless of whether the
  /// email actually matches an account. Emails a 5-minute one-time code
  /// (2026-08-29, replacing the old clickable link, by request — see
  /// `App\Services\OtpPasswordResetBroker`) completed natively in-app via
  /// [resetPasswordWithOtp] rather than handing off to a browser.
  Future<String> sendPasswordResetCode(String email) async {
    final data = await _client.postJson('/forgot-password', body: {'email': email}) as Map<String, dynamic>;
    return data['message'] as String;
  }

  /// Completes the reset [sendPasswordResetCode] started. Throws
  /// [ApiException] (422, `message`) if the code is wrong/expired — the
  /// server re-validates the code against whichever email is submitted
  /// here (see `Api\PasswordResetController::reset()`), same as the web
  /// form.
  Future<String> resetPasswordWithOtp({
    required String email,
    required String otp,
    required String password,
    required String passwordConfirmation,
  }) async {
    final data = await _client.postJson('/reset-password', body: {
      'email': email,
      'otp': otp,
      'password': password,
      'password_confirmation': passwordConfirmation,
    }) as Map<String, dynamic>;
    return data['message'] as String;
  }

  Future<AuthAccount> fetchMe(AccountType type) async {
    final data = await _client.getJson('/me') as Map<String, dynamic>;

    return switch (type) {
      AccountType.staff => StaffAccount.fromJson(data),
      AccountType.doctor => DoctorAccount.fromJson(data),
    };
  }

  /// Best-effort: an already-expired/revoked token may itself 401 here, but
  /// the caller (`AuthController.logout`) clears local state regardless.
  Future<void> logout() async {
    try {
      await _client.postJson('/logout');
    } catch (_) {
      // ignore — local session clearing proceeds either way.
    }
  }
}
