import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/support_code.dart';

final supportCodesRepositoryProvider = Provider<SupportCodesRepository>((ref) {
  return SupportCodesRepository(ref.watch(apiClientProvider));
});

/// Care cards, "بطاقات الرعاية" (2026-11-01, by request): the web
/// `/support-codes` page's API. See App\Support\SupportCodes on the server.
class SupportCodesRepository {
  SupportCodesRepository(this._client);
  final ApiClient _client;

  Future<SupportCodePage> list({String? status, String? search, int? batch, int page = 1, int perPage = 100}) async {
    final data = await _client.getJson('/support-codes', query: {
      if (status != null) 'status': status,
      if (search != null && search.isNotEmpty) 'search': search,
      if (batch != null) 'batch': batch,
      'page': page,
      'per_page': perPage,
    }) as Map<String, dynamic>;
    return SupportCodePage.fromJson(data);
  }

  /// Every active code of [batch] (or all active ones), for printing cards.
  Future<List<SupportCode>> activeCodes({int? batch}) async {
    final out = <SupportCode>[];
    var page = 1;
    while (true) {
      final p = await list(status: 'active', batch: batch, page: page, perPage: 500);
      out.addAll(p.codes);
      if (page >= p.lastPage) break;
      page++;
    }
    return out;
  }

  /// Makes [count] new codes in one batch; returns them.
  Future<List<SupportCode>> generate(int count, {String? note}) async {
    final data = await _client.postJson('/support-codes', body: {
      'count': count,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    }) as Map<String, dynamic>;
    return [for (final e in data['data'] as List<dynamic>) SupportCode.fromJson(e as Map<String, dynamic>)];
  }

  /// Stops (or starts again) unused codes by id or a whole batch; returns the server's message.
  Future<String> setDisabled({List<int> ids = const [], int? batch, required bool disabled}) async {
    final data = await _client.postJson('/support-codes/status', body: {
      'ids': ids,
      if (batch != null) 'batch': batch,
      'disabled': disabled,
    }) as Map<String, dynamic>;
    return data['message'] as String? ?? '';
  }

  /// Checks a typed code at the desk; throws the server's 422 when it cannot be used.
  Future<String> check(String code) async {
    final data = await _client.postJson('/support-codes/check', body: {'code': code}) as Map<String, dynamic>;
    return data['message'] as String? ?? '';
  }
}
