import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/network/paginated.dart';
import '../data/tasks_admin_repository.dart';
import '../domain/task_admin.dart';

/// Keyed on `(stageId, departmentId)` — the list screen only creates this
/// once both are chosen (see `TasksAdminRepository.list()`'s doc comment),
/// mirroring `patientRegistrationListProvider`'s family shape.
final taskAdminListProvider =
    FutureProvider.autoDispose.family<Paginated<TaskAdmin>, ({int stageId, int departmentId})>((ref, filter) {
  return ref.watch(tasksAdminRepositoryProvider).list(stageId: filter.stageId, departmentId: filter.departmentId);
});

final taskAdminProvider = FutureProvider.autoDispose.family<TaskAdmin, int>((ref, id) {
  return ref.watch(tasksAdminRepositoryProvider).fetch(id);
});

final taskDepartmentsProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(lookupRepositoryProvider).departments();
});

final taskStagesProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(lookupRepositoryProvider).stages();
});

final taskEducationTypesProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(lookupRepositoryProvider).educationTypes();
});

final taskCaseSheetTypesProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(lookupRepositoryProvider).caseSheetTypes();
});
