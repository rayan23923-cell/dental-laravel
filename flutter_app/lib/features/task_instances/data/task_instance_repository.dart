import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/my_task_department.dart';
import '../domain/pending_task.dart';
import '../domain/task_instance.dart';
import '../domain/task_instance_status.dart';

final taskInstanceRepositoryProvider = Provider<TaskInstanceRepository>((ref) {
  return TaskInstanceRepository(ref.watch(apiClientProvider));
});

class TaskInstanceRepository {
  TaskInstanceRepository(this._client);
  final ApiClient _client;

  /// The doctor's own department-grouped task summary — `GET
  /// /my-task-progress` (`Api\TaskProgressController::mine()`). Reconstructs
  /// the full set of required slots per task, including ones never
  /// started (which have no `TaskInstance` row at all), unlike a plain
  /// flat query over existing instances.
  Future<List<MyTaskDepartment>> mineProgress() async {
    final data =
        await _client.getJson('/my-task-progress') as Map<String, dynamic>;
    return (data['departments'] as List<dynamic>)
        .map((e) => MyTaskDepartment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TaskInstance> show(int id) async {
    final data =
        await _client.getJson('/task-instances/$id') as Map<String, dynamic>;
    return TaskInstance.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<TaskInstance> updateStatus(
    int id, {
    required TaskInstanceStatus status,
    double? grade,
    String? notes,
  }) async {
    final data =
        await _client.putJson(
              '/task-instances/$id',
              body: {
                'status': status.toJson(),
                if (grade != null) 'grade': grade,
                if (notes != null) 'notes': notes,
              },
            )
            as Map<String, dynamic>;

    return TaskInstance.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// "رموز المهام المعلقة" — every task type in the doctor's own stage
  /// they have no instance of at all yet, `GET /pending-tasks`
  /// (`Api\PendingTaskQrController::index()`, the same
  /// `PendingTaskFinder::forDoctor()` list the web's own dedicated page
  /// uses). Distinct from `mineProgress()`'s per-*slot* rows — this is
  /// per-*task-type*, matching the dedicated page's own grid.
  Future<List<PendingTask>> pendingTasksQr() async {
    final data =
        await _client.getJson('/pending-tasks') as Map<String, dynamic>;
    return (data['data'] as List<dynamic>)
        .map((e) => PendingTask.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Resolves a scanned QR code's raw decoded text to its task instance.
  Future<TaskInstance> scan(String payload) async {
    final data =
        await _client.postJson(
              '/task-instances/scan',
              body: {'payload': payload},
            )
            as Map<String, dynamic>;
    return TaskInstance.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// "شكرا، تم توثيقه ورقياً" (2026-08-28) — see
  /// `Api\TaskInstanceController::confirmPaper()`'s doc comment: purely a
  /// non-exclusive confirmation tag, never blocks or hides the electronic
  /// case-sheet flow.
  Future<TaskInstance> confirmPaper(int id) async {
    final data =
        await _client.postJson('/task-instances/$id/confirm-paper')
            as Map<String, dynamic>;
    return TaskInstance.fromJson(data['data'] as Map<String, dynamic>);
  }
}
