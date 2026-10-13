import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';

final paperPhotosRepositoryProvider = Provider<PaperPhotosRepository>((ref) {
  return PaperPhotosRepository(ref.watch(apiClientProvider));
});

class PaperPhoto {
  const PaperPhoto({required this.id, required this.url});

  factory PaperPhoto.fromJson(Map<String, dynamic> json) =>
      PaperPhoto(id: json['id'] as int, url: json['url'] as String? ?? '');

  final int id;
  final String url;
}

/// Photos of a task's paper case sheet (2026-10-13) — the same
/// `TaskInstanceAttachmentController` the web uses. Staff go through the
/// task-progress routes; a doctor through their own `my-task-instances`.
class PaperPhotosRepository {
  PaperPhotosRepository(this._client);
  final ApiClient _client;

  String _base(bool doctor, int instanceId) =>
      doctor ? '/my-task-instances/$instanceId/attachments' : '/task-progress/instances/$instanceId/attachments';

  List<PaperPhoto> _parse(dynamic data) => ((data as Map<String, dynamic>)['data'] as List<dynamic>)
      .map((e) => PaperPhoto.fromJson(e as Map<String, dynamic>))
      .toList();

  Future<List<PaperPhoto>> list({required bool doctor, required int instanceId}) async {
    return _parse(await _client.getJson(_base(doctor, instanceId)));
  }

  Future<List<PaperPhoto>> upload({required bool doctor, required int instanceId, required XFile photo}) async {
    final formData = FormData.fromMap({
      'photo': MultipartFile.fromBytes(await photo.readAsBytes(), filename: photo.name),
    });
    return _parse(await _client.postFile(_base(doctor, instanceId), formData: formData));
  }

  Future<void> delete({required bool doctor, required int photoId}) {
    return _client.deleteJson(doctor ? '/my-task-instances/attachments/$photoId' : '/task-progress/attachments/$photoId');
  }
}
