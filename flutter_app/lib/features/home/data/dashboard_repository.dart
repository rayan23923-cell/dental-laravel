import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/dashboard_data.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(apiClientProvider));
});

/// The staff dashboard's figures (`Api\DashboardController`, 2026-10-17):
/// the same numbers the web dashboard shows, and its per-education-type
/// task section loaded on demand.
class DashboardRepository {
  DashboardRepository(this._client);
  final ApiClient _client;

  Future<DashboardData> fetch() async {
    final data = await _client.getJson('/dashboard') as Map<String, dynamic>;
    return DashboardData.fromJson(data);
  }

  Future<DeskPanels> fetchDesk() async {
    final data = await _client.getJson('/dashboard/desk') as Map<String, dynamic>;
    return DeskPanels.fromJson(data);
  }

  Future<List<DashboardDepartment>> tasksByEducationType(int educationTypeId) async {
    final data = await _client.getJson('/dashboard/tasks-by-education-type/$educationTypeId') as Map<String, dynamic>;
    return [
      for (final d in data['departments'] as List<dynamic>? ?? const [])
        DashboardDepartment.fromJson(d as Map<String, dynamic>),
    ];
  }
}

final dashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) {
  return ref.watch(dashboardRepositoryProvider).fetch();
});

final deskPanelsProvider = FutureProvider.autoDispose<DeskPanels>((ref) {
  return ref.watch(dashboardRepositoryProvider).fetchDesk();
});

final dashboardTasksByEducationTypeProvider =
    FutureProvider.autoDispose.family<List<DashboardDepartment>, int>((ref, educationTypeId) {
  return ref.watch(dashboardRepositoryProvider).tasksByEducationType(educationTypeId);
});
