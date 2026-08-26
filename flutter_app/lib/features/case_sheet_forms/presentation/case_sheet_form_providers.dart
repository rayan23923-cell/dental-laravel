import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated.dart';
import '../data/case_sheet_form_repository.dart';
import '../data/case_sheet_record_repository.dart';
import '../domain/case_sheet_form_schema.dart';

final caseSheetFormSchemaProvider = FutureProvider.autoDispose.family<CaseSheetFormSchema, String>((ref, resource) {
  return ref.watch(caseSheetFormRepositoryProvider).fetch(resource);
});

final caseSheetResourceListProvider = FutureProvider.autoDispose<List<(String, String)>>((ref) {
  return ref.watch(caseSheetFormRepositoryProvider).listResources();
});

final caseSheetRecordListProvider =
    FutureProvider.autoDispose.family<Paginated<Map<String, dynamic>>, String>((ref, resource) {
  return ref.watch(caseSheetRecordRepositoryProvider).list(resource);
});

final caseSheetRecordProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, (String resource, int id)>((ref, args) {
  return ref.watch(caseSheetRecordRepositoryProvider).fetch(args.$1, args.$2);
});
