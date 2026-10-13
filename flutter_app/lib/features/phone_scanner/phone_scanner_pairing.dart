import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

final phoneScannerPairingProvider = Provider<PhoneScannerPairing>((ref) {
  return PhoneScannerPairing(ref.watch(apiClientProvider));
});

/// A pairing as the server's `ScannerPairing::forDesktop()` returns it.
class PhoneScannerSession {
  const PhoneScannerSession({
    required this.id,
    required this.code,
    required this.url,
    required this.enterUrl,
    required this.qrDataUri,
    required this.phoneJoined,
    required this.expiresAt,
  });

  final int id;
  final String code;
  final String url;
  final String enterUrl;
  final String qrDataUri;
  final bool phoneJoined;
  final DateTime expiresAt;

  bool get expired => expiresAt.isBefore(DateTime.now());

  /// The QR picture: the server sends a `data:image/png;base64,...` URI.
  List<int> get qrPng => base64Decode(qrDataUri.substring(qrDataUri.indexOf(',') + 1));

  factory PhoneScannerSession.fromJson(Map<String, dynamic> json) => PhoneScannerSession(
    id: json['id'] as int,
    code: json['code'] as String,
    url: json['url'] as String,
    enterUrl: json['enter_url'] as String,
    qrDataUri: json['qr'] as String,
    phoneJoined: json['phone_joined'] == true,
    expiresAt: DateTime.parse(json['expires_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'url': url,
    'enter_url': enterUrl,
    'qr': qrDataUri,
    'phone_joined': phoneJoined,
    'expires_at': expiresAt.toIso8601String(),
  };

  PhoneScannerSession withJoined(bool joined) => PhoneScannerSession(
    id: id,
    code: code,
    url: url,
    enterUrl: enterUrl,
    qrDataUri: qrDataUri,
    phoneJoined: joined,
    expiresAt: expiresAt,
  );
}

/// What one poll found: whether the phone has opened the link, and the
/// codes it scanned since the last poll.
class PhoneScanBatch {
  const PhoneScanBatch(this.phoneJoined, this.payloads);
  final bool phoneJoined;
  final List<String> payloads;
}

/// The Windows app's side of "the phone as a QR scanner" (2026-10-12, by
/// request), the same flow as the web app's `remoteScanner.js`: open a
/// pairing (`POST /scanner-pairings`), show its QR and six-digit code,
/// then poll `/scanner-pairings/{id}/scans?after=` for what the phone
/// read. The pairing and the last scan id are kept in shared_preferences
/// so reopening a scanner keeps the same phone linked.
class PhoneScannerPairing {
  PhoneScannerPairing(this._client);
  final ApiClient _client;

  static const _kPairing = 'phone_scanner_pairing';
  static const _kLastId = 'phone_scanner_last_id';

  Future<PhoneScannerSession?> saved() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPairing);
    if (raw == null) return null;
    try {
      final session = PhoneScannerSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (session.expired) {
        await _clear();
        return null;
      }
      return session;
    } catch (_) {
      await _clear();
      return null;
    }
  }

  Future<PhoneScannerSession> open() async {
    final data = await _client.postJson('/scanner-pairings') as Map<String, dynamic>;
    final session = PhoneScannerSession.fromJson(data['data'] as Map<String, dynamic>);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPairing, jsonEncode(session.toJson()));
    await prefs.setInt(_kLastId, 0);
    return session;
  }

  Future<void> close(PhoneScannerSession session) async {
    await _clear();
    try {
      await _client.deleteJson('/scanner-pairings/${session.id}');
    } catch (_) {
      // Already gone on the server: nothing left to end.
    }
  }

  /// New scans since the last call, or null once the pairing has ended
  /// (expired, or replaced by a pairing opened elsewhere).
  Future<PhoneScanBatch?> poll(PhoneScannerSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final after = prefs.getInt(_kLastId) ?? 0;
    try {
      final data =
          await _client.getJson('/scanner-pairings/${session.id}/scans', query: {'after': after})
              as Map<String, dynamic>;
      final body = data['data'] as Map<String, dynamic>;
      final scans = (body['scans'] as List<dynamic>).cast<Map<String, dynamic>>();
      if (scans.isNotEmpty) await prefs.setInt(_kLastId, scans.last['id'] as int);
      return PhoneScanBatch(body['phone_joined'] == true, [for (final s in scans) s['payload'] as String]);
    } on ServerException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 410) {
        await _clear();
        return null;
      }
      rethrow;
    }
  }

  Future<void> _clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPairing);
    await prefs.remove(_kLastId);
  }
}
