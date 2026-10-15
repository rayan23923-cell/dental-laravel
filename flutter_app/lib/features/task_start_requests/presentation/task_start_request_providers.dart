import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/task_start_request_repository.dart';
import '../domain/task_start_request.dart';

/// The doctor's own start requests.
final myTaskStartRequestsProvider = FutureProvider.autoDispose<List<TaskStartRequest>>((ref) {
  return ref.watch(taskStartRequestRepositoryProvider).mine();
});

/// Staff: requests to review, for the "الطلبات" tab of task progress.
final taskStartRequestBoardProvider = FutureProvider.autoDispose<TaskStartRequestBoard>((ref) {
  return ref.watch(taskStartRequestRepositoryProvider).board();
});
