import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';
import '../domain/task_admin.dart';
import '../domain/task_instance_admin.dart';
import '../domain/task_scoring.dart';

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

  /// The task with its instances (each with its doctor) — the web's
  /// Tasks/Show (2026-10-17).
  Future<({TaskAdmin task, List<TaskInstanceAdmin> instances})> fetchWithInstances(int id) async {
    final data = await _client.getJson('/tasks/$id') as Map<String, dynamic>;
    final json = data['data'] as Map<String, dynamic>;
    return (
      task: TaskAdmin.fromJson(json),
      instances: [
        for (final i in json['instances'] as List<dynamic>? ?? const [])
          TaskInstanceAdmin.fromJson(i as Map<String, dynamic>),
      ],
    );
  }

  /// The doctors this task can be assigned to (its own academic year, plus
  /// session-less doctors), as the web's "تخصيص لطبيب" select offers.
  Future<List<({int id, String name})>> assignableDoctors(int taskId) async {
    final data = await _client.getJson('/tasks/$taskId/assignable-doctors') as Map<String, dynamic>;
    return [
      for (final d in data['data'] as List<dynamic>? ?? const [])
        (id: (d as Map<String, dynamic>)['id'] as int, name: d['name'] as String? ?? ''),
    ];
  }

  Future<void> assign({required int taskId, required int doctorId}) =>
      _client.postJson('/task-instances', body: {'task_id': taskId, 'doctor_id': doctorId});

  Future<void> updateInstance(int id, {required String status, double? grade, String? notes}) =>
      _client.putJson('/task-instances/$id', body: {'status': status, 'grade': grade, 'notes': notes});

  Future<void> deleteInstance(int id) => _client.deleteJson('/task-instances/$id');

  Future<TaskAdmin> create(Map<String, dynamic> payload) async {
    final data = await _client.postJson('/tasks', body: payload) as Map<String, dynamic>;
    return TaskAdmin.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<TaskAdmin> update(int id, Map<String, dynamic> payload) async {
    final data = await _client.putJson('/tasks/$id', body: payload) as Map<String, dynamic>;
    return TaskAdmin.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<void> delete(int id) => _client.deleteJson('/tasks/$id');

  /// The requirements tables a case-sheet type pre-fills in the add-task
  /// form (`Api\TaskController::scoringTemplates()`), keyed by type id.
  Future<Map<int, ScoringTemplate>> scoringTemplates() async {
    final data = await _client.getJson('/tasks/scoring-templates') as Map<String, dynamic>;
    final templates = data['data'] as Map<String, dynamic>? ?? const {};
    return {
      for (final e in templates.entries)
        if (int.tryParse(e.key) != null) int.parse(e.key): ScoringTemplate.fromJson(e.value as Map<String, dynamic>),
    };
  }
}
