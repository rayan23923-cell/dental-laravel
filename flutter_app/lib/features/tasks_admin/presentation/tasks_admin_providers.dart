import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/network/paginated.dart';
import '../data/tasks_admin_repository.dart';
import '../domain/task_admin.dart';
import '../domain/task_instance_admin.dart';
import '../domain/task_scoring.dart';

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

/// Requirements tables by case-sheet type id (2026-10-17), for the add-task form.
final taskScoringTemplatesProvider = FutureProvider.autoDispose<Map<int, ScoringTemplate>>((ref) {
  return ref.watch(tasksAdminRepositoryProvider).scoringTemplates();
});

/// The task detail screen's task and its instances (2026-10-17).
final taskWithInstancesProvider = FutureProvider.autoDispose
    .family<({TaskAdmin task, List<TaskInstanceAdmin> instances}), int>((ref, id) {
  return ref.watch(tasksAdminRepositoryProvider).fetchWithInstances(id);
});

final taskAssignableDoctorsProvider = FutureProvider.autoDispose.family<List<({int id, String name})>, int>((ref, taskId) {
  return ref.watch(tasksAdminRepositoryProvider).assignableDoctors(taskId);
});
