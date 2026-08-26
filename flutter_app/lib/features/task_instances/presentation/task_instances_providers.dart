import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/task_instance_repository.dart';
import '../domain/my_task_department.dart';
import '../domain/task_instance.dart';

final taskInstanceDetailProvider = FutureProvider.autoDispose.family<TaskInstance, int>((ref, id) {
  return ref.watch(taskInstanceRepositoryProvider).show(id);
});

/// The doctor's own department-grouped task summary — see
/// `TaskInstanceRepository.mineProgress()`.
final myTaskProgressProvider = FutureProvider.autoDispose<List<MyTaskDepartment>>((ref) {
  return ref.watch(taskInstanceRepositoryProvider).mineProgress();
});

/// After any write (status update, a scan resolving to an instance), both
/// the list and that instance's own detail cache need to reflect the new
/// state — invalidating both here keeps that in one place instead of
/// repeated at every call site.
void invalidateTaskInstance(WidgetRef ref, int id) {
  ref.invalidate(myTaskProgressProvider);
  ref.invalidate(taskInstanceDetailProvider(id));
}
