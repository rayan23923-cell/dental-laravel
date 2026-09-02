import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/offline/local_json_store.dart';
import '../domain/account_type.dart';

final authOfflineCacheProvider = Provider<AuthOfflineCache>((ref) {
  return AuthOfflineCache(ref.watch(localJsonStoreProvider));
});

/// Caches the raw `/me` response so `AuthController.build()` can restore a
/// session without a network round-trip — see "Offline mode for Flutter
/// case sheets" (the app-can't-open-offline half of that plan). Stores the
/// *raw* JSON, not a parsed `AuthAccount`, so it round-trips through the
/// existing `StaffAccount.fromJson`/`DoctorAccount.fromJson` unchanged —
/// no new `toJson()` needed anywhere.
class AuthOfflineCache {
  AuthOfflineCache(this._store);
  final LocalJsonStore _store;

  static const _prefix = 'offline_auth_account::';

  Future<void> cacheAccount(AccountType type, Map<String, dynamic> rawJson) {
    return _store.putJson('$_prefix${type.name}', rawJson);
  }

  Future<Map<String, dynamic>?> readAccount(AccountType type) {
    return _store.getJson('$_prefix${type.name}');
  }
}
