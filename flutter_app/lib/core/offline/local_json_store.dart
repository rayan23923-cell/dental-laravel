import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final localJsonStoreProvider = Provider<LocalJsonStore>((ref) => const LocalJsonStore());

/// Generic JSON-blob-per-key persistence over `shared_preferences` — the
/// same flat-key approach `PrinterSettingsRepository` already uses, just
/// storing whole JSON values instead of individual scalar prefs. Backs the
/// case-sheet offline cache/queue and the auth account cache; the data
/// volume here (a handful of case-sheet records, never more than a few KB
/// each) doesn't justify a real local database.
class LocalJsonStore {
  const LocalJsonStore();

  Future<void> putJson(String key, Object? value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  Future<Map<String, dynamic>?> getJson(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  /// Client-side filter — `shared_preferences` has no native prefix query,
  /// and its keyspace is shared with every other feature that uses it
  /// (`PrinterSettingsRepository`, etc.), so every caller here scopes its
  /// own keys with a distinct prefix before ever calling this.
  Future<List<String>> keysWithPrefix(String prefix) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
  }
}
