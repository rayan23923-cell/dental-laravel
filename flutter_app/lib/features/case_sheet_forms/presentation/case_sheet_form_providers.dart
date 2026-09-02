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

/// A brand-new sheet's patient-field prefill, resolved from whichever
/// patient this task instance was started for (2026-09-02) — see
/// `CaseSheetOpenResult.patientPrefill`'s own doc comment.
/// `CaseSheetFormScreen` watches this only when actually creating
/// (`recordId == null`) with a known `taskInstanceId`; `openFor()` already
/// has its own offline-cache fallback, so this needs none of its own.
final caseSheetPatientPrefillProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, taskInstanceId) async {
  final result = await ref.watch(caseSheetRecordRepositoryProvider).openFor(taskInstanceId);
  return result.patientPrefill;
});
