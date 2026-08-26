import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/taxonomy_item.dart';

final taxonomyRepositoryProvider = Provider<TaxonomyRepository>((ref) {
  return TaxonomyRepository(ref.watch(apiClientProvider));
});

/// CRUD for education-types/stages/departments — plain (non-paginated,
/// non-`{data:}`-wrapped) JSON arrays and objects, matching
/// `Api\LookupController`'s existing shape exactly (see `TaxonomyItem`'s
/// own doc comment for why that differs from the rest of this API).
class TaxonomyRepository {
  TaxonomyRepository(this._client);
  final ApiClient _client;

  Future<List<TaxonomyItem>> list(TaxonomyKind kind) async {
    final data = await _client.getJson('/${kind.endpoint}') as List<dynamic>;
    return data.map((e) => TaxonomyItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<TaxonomyItem> create(TaxonomyKind kind, Map<String, dynamic> payload) async {
    final data = await _client.postJson('/${kind.endpoint}', body: payload) as Map<String, dynamic>;
    return TaxonomyItem.fromJson(data);
  }

  Future<TaxonomyItem> update(TaxonomyKind kind, int id, Map<String, dynamic> payload) async {
    final data = await _client.putJson('/${kind.endpoint}/$id', body: payload) as Map<String, dynamic>;
    return TaxonomyItem.fromJson(data);
  }

  Future<void> delete(TaxonomyKind kind, int id) => _client.deleteJson('/${kind.endpoint}/$id');
}
