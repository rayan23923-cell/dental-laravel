import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/case_sheet_types_admin_repository.dart';
import '../domain/case_sheet_type_admin.dart';

final caseSheetTypeListProvider = FutureProvider.autoDispose<List<CaseSheetTypeAdmin>>((ref) {
  return ref.watch(caseSheetTypesAdminRepositoryProvider).list();
});
