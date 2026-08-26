import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/taxonomy_repository.dart';
import '../domain/taxonomy_item.dart';

final taxonomyListProvider = FutureProvider.autoDispose.family<List<TaxonomyItem>, TaxonomyKind>((ref, kind) {
  return ref.watch(taxonomyRepositoryProvider).list(kind);
});
