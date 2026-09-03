import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';

final endodonticsXrayRepositoryProvider = Provider<EndodonticsXrayRepository>((ref) {
  return EndodonticsXrayRepository(ref.watch(apiClientProvider));
});

/// `POST /endodontics-xrays` — mirrors `Api\EndodonticsXrayController`: one
/// image in, the stored path back. See that controller's own doc comment
/// for why this is a standalone upload rather than part of the case
/// sheet's own update payload.
class EndodonticsXrayRepository {
  EndodonticsXrayRepository(this._client);
  final ApiClient _client;

  Future<String> upload(XFile image) async {
    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(await image.readAsBytes(), filename: image.name),
    });
    final data = await _client.postFile('/endodontics-xrays', formData: formData) as Map<String, dynamic>;
    return data['path'] as String;
  }
}
