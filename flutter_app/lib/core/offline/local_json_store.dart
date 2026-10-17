import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

final localJsonStoreProvider = Provider<LocalJsonStore>((ref) => const LocalJsonStore());

/// Generic JSON-blob-per-key persistence over `shared_preferences` — the
/// same flat-key approach `PrinterSettingsRepository` already uses, just
/// storing whole JSON values instead of individual scalar prefs. Backs the
/// case-sheet offline cache/queue and the auth account cache; the data
/// volume here (a handful of case-sheet records, never more than a few KB
/// each) doesn't justify a real local database.
///
/// Keys are per server (2026-10-17): cached records and queued offline
/// edits belong to the server they came from, so with the clinic's
/// offline server chosen every key gets [AppConfig.storageNamespace] in
/// front (the cloud's keys are unchanged). Callers never see the prefix.
class LocalJsonStore {
  const LocalJsonStore({String Function()? namespace}) : _namespace = namespace;

  final String Function()? _namespace;

  String get _ns => _namespace?.call() ?? AppConfig.storageNamespace;

  Future<void> putJson(String key, Object? value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_ns$key', jsonEncode(value));
  }

  Future<Map<String, dynamic>?> getJson(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_ns$key');
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
    await prefs.remove('$_ns$key');
  }

  /// Client-side filter — `shared_preferences` has no native prefix query,
  /// and its keyspace is shared with every other feature that uses it
  /// (`PrinterSettingsRepository`, etc.), so every caller here scopes its
  /// own keys with a distinct prefix before ever calling this.
  Future<List<String>> keysWithPrefix(String prefix) async {
    final prefs = await SharedPreferences.getInstance();
    final ns = _ns;
    return prefs.getKeys().where((k) => k.startsWith('$ns$prefix')).map((k) => k.substring(ns.length)).toList();
  }
}
