import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';
import '../domain/task_admin.dart';

final tasksAdminRepositoryProvider = Provider<TasksAdminRepository>((ref) {
  return TasksAdminRepository(ref.watch(apiClientProvider));
});

/// CRUD for the Task catalogue (`/tasks`, `permission:tasks,*`) — the
/// admin/write side; `core/data/lookup_repository.dart`'s `tasks()`
/// covers the read-only-picker side (e.g. the appointment form).
class TasksAdminRepository {
  TasksAdminRepository(this._client);
  final ApiClient _client;

  /// [stageId]/[departmentId] mirror `Api\TaskController::index()`'s
  /// optional filters — the screen only calls this once both are set
  /// (matching the legacy admin/manage_tasks.php's "hidden until all
  /// three are chosen" behavior; the third, education type, has no
  /// server-side effect since `tasks` has no such column).
  Future<Paginated<TaskAdmin>> list({int? stageId, int? departmentId}) async {
    final data = await _client.getJson('/tasks', query: {
      if (stageId != null) 'stage_id': stageId,
      if (departmentId != null) 'department_id': departmentId,
    }) as Map<String, dynamic>;
    return Paginated.fromJson(data, TaskAdmin.fromJson);
  }

  Future<TaskAdmin> fetch(int id) async {
    final data = await _client.getJson('/tasks/$id') as Map<String, dynamic>;
    return TaskAdmin.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<TaskAdmin> create(Map<String, dynamic> payload) async {
    final data = await _client.postJson('/tasks', body: payload) as Map<String, dynamic>;
    return TaskAdmin.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<TaskAdmin> update(int id, Map<String, dynamic> payload) async {
    final data = await _client.putJson('/tasks/$id', body: payload) as Map<String, dynamic>;
    return TaskAdmin.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<void> delete(int id) => _client.deleteJson('/tasks/$id');
}
