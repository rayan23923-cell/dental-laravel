import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/task_progress_repository.dart';
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

final taskProgressGroupProvider = FutureProvider.autoDispose.family<TaskProgressGroupDetail, int>((ref, groupId) {
  return ref.watch(taskProgressRepositoryProvider).fetchGroup(groupId);
});
