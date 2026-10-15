import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../domain/task_start_request.dart';

final taskStartRequestRepositoryProvider = Provider<TaskStartRequestRepository>((ref) {
  return TaskStartRequestRepository(ref.watch(apiClientProvider));
});

/// "طلبات بدء المهام" (2026-10-14) — the same `TaskStartRequestController`
/// the web uses: a doctor's own requests under `/my-task-start-requests`,
/// the staff review list under `/task-progress/requests`.
class TaskStartRequestRepository {
  TaskStartRequestRepository(this._client);
  final ApiClient _client;

  Future<List<TaskStartRequest>> mine() async {
    final data = await _client.getJson('/my-task-start-requests') as Map<String, dynamic>;
    return (data['data'] as List<dynamic>).map((e) => TaskStartRequest.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> create({required int taskId, required String formType, XFile? photo, String? notes}) async {
    final formData = FormData.fromMap({
      'task_id': taskId,
      'form_type': formType,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (photo != null) 'photo': MultipartFile.fromBytes(await photo.readAsBytes(), filename: photo.name),
    });
    await _client.postFile('/my-task-start-requests', formData: formData);
  }

  Future<void> cancel(int id) => _client.deleteJson('/my-task-start-requests/$id');

  Future<TaskStartRequestBoard> board() async {
    final data = await _client.getJson('/task-progress/requests') as Map<String, dynamic>;
    return TaskStartRequestBoard.fromJson(data);
  }

  Future<void> approve(int id, {String? note}) => _client.postJson('/task-progress/requests/$id/approve', body: {'note': note});

  Future<void> reject(int id, {String? note}) => _client.postJson('/task-progress/requests/$id/reject', body: {'note': note});
}
