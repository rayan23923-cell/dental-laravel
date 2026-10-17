import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/domain/account_type.dart';
import '../config/app_config.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// Keychain/Keystore-backed persistence for the Sanctum bearer token and
/// which login endpoint it came from (see [AccountType] for why the latter
/// is needed). Pure key/value wrapper — no business logic.
///
/// A token belongs to the server that issued it (2026-10-17, cloud or the
/// clinic's offline server): the server's id is stored with it, and a
/// token saved for another server reads as "not logged in". Tokens saved
/// before this existed have no id and belong to the cloud server.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage, String Function()? currentServerId})
      : _storage = storage ?? const FlutterSecureStorage(),
        _currentServerId = currentServerId ?? (() => AppConfig.serverId);

  final FlutterSecureStorage _storage;
  final String Function() _currentServerId;

  static const _kToken = 'auth_token';
  static const _kAccountType = 'account_type';
  static const _kServer = 'auth_server';
  static const _legacyServerId = 'cloud';

  Future<void> save({required String token, required AccountType accountType}) async {
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kAccountType, value: accountType.name);
    await _storage.write(key: _kServer, value: _currentServerId());
  }

  Future<bool> _forCurrentServer() async {
    final owner = await _storage.read(key: _kServer) ?? _legacyServerId;
    return owner == _currentServerId();
  }

  Future<String?> readToken() async {
    if (!await _forCurrentServer()) return null;
    return _storage.read(key: _kToken);
  }

  Future<AccountType?> readAccountType() async {
    if (!await _forCurrentServer()) return null;
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
    await _storage.delete(key: _kServer);
  }
}
