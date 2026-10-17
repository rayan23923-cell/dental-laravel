import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/task_progress_repository.dart';
import '../domain/doctor_progress.dart';
import '../domain/task_progress_group.dart';

/// Keyed on the current filter selection, same shape as
/// `tasks_admin_providers.dart`'s `taskAdminListProvider` — a fresh fetch
/// on every filter change, matching the web page's own re-fetch-on-every-
/// filter-change behaviour rather than a client-side cache of every
/// possible combination.
final taskProgressFiltersProvider =
    FutureProvider.autoDispose.family<TaskProgressFilters, ({String? day, int? educationTypeId, int? stageId})>((ref, filter) {
  return ref.watch(taskProgressRepositoryProvider).fetchFilters(
        day: filter.day,
        educationTypeId: filter.educationTypeId,
        stageId: filter.stageId,
      );
});

/// One group's matrix, or — while groups are turned off in clinic settings
/// — every doctor of one stage. Exactly one of the two ids is set.
typedef TaskProgressDetailKey = ({int? groupId, int? stageId});

final taskProgressGroupProvider =
    FutureProvider.autoDispose.family<TaskProgressGroupDetail, TaskProgressDetailKey>((ref, key) {
  final repository = ref.watch(taskProgressRepositoryProvider);
  return key.groupId != null ? repository.fetchGroup(key.groupId!) : repository.fetchStage(key.stageId!);
});

/// One doctor's progress, opened from their ID card QR (2026-10-14 on the web).
final doctorProgressProvider = FutureProvider.autoDispose.family<DoctorProgress, int>((ref, doctorId) {
  return ref.watch(taskProgressRepositoryProvider).fetchDoctorProgress(doctorId);
});
