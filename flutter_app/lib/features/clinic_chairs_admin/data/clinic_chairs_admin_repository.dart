import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/clinic_chair_admin.dart';

final clinicChairsAdminRepositoryProvider = Provider<ClinicChairsAdminRepository>((ref) {
  return ClinicChairsAdminRepository(ref.watch(apiClientProvider));
});

/// Wraps `/clinic-chairs` — plain JSON, matching `GroupsAdminRepository`'s
/// own convention (`Api\ClinicChairController` mirrors `Api\GroupController`'s
/// unwrapped-response shape, not this API's usual REST envelope).
class ClinicChairsAdminRepository {
  ClinicChairsAdminRepository(this._client);
  final ApiClient _client;

  Future<ClinicChairsBoard> fetchBoard() async {
    final data = await _client.getJson('/clinic-chairs') as Map<String, dynamic>;
    return ClinicChairsBoard.fromJson(data);
  }

  Future<void> addChair({int? rowNumber}) =>
      _client.postJson('/clinic-chairs', body: {if (rowNumber != null) 'row_number': rowNumber});

  /// `clearAssignment: true` unassigns the chair — sends `group_id: null`
  /// with no `doctor_id` key at all, matching the server's own "unassign
  /// clears both together" rule (`ClinicChairController::update()`'s doc
  /// comment).
  Future<void> assignChairToGroup(int chairId, int groupId) =>
      _client.putJson('/clinic-chairs/$chairId', body: {'group_id': groupId});

  Future<void> unassignChair(int chairId) => _client.putJson('/clinic-chairs/$chairId', body: {'group_id': null});

  Future<void> moveChair(int chairId, {required int rowNumber, required int columnNumber}) => _client.putJson(
        '/clinic-chairs/$chairId/move',
        body: {'row_number': rowNumber, 'column_number': columnNumber},
      );

  Future<void> deleteChair(int chairId) => _client.deleteJson('/clinic-chairs/$chairId');

  /// Returns the server's own confirmation message ("N doctor(s) assigned
  /// to chairs." / "Every doctor in this group already has a chair.") so
  /// the screen can show it verbatim in a SnackBar.
  Future<String> assignGroup(int groupId) async {
    final data = await _client.postJson('/clinic-chairs/assign-group', body: {'group_id': groupId}) as Map<String, dynamic>;
    return data['message'] as String? ?? '';
  }
}
