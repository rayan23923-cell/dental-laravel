import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/domain/account_type.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// Keychain/Keystore-backed persistence for the Sanctum bearer token and
/// which login endpoint it came from (see [AccountType] for why the latter
/// is needed). Pure key/value wrapper — no business logic.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kToken = 'auth_token';
  static const _kAccountType = 'account_type';

  Future<void> save({required String token, required AccountType accountType}) async {
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kAccountType, value: accountType.name);
  }

  Future<String?> readToken() => _storage.read(key: _kToken);

  Future<AccountType?> readAccountType() async {
    final raw = await _storage.read(key: _kAccountType);
    if (raw == null) return null;
    try {
      return AccountType.values.byName(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kAccountType);
  }
}
