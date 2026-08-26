import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';
import '../domain/activity_log_entry.dart';

final activityLogsRepositoryProvider = Provider<ActivityLogsRepository>((ref) {
  return ActivityLogsRepository(ref.watch(apiClientProvider));
});

/// `/activity-logs` — the standard Laravel `paginate()->response()`
/// envelope (`Paginated<T>`), unlike most of the admin endpoints this
/// session added, which return plain arrays.
class ActivityLogsRepository {
  ActivityLogsRepository(this._client);
  final ApiClient _client;

  Future<Paginated<ActivityLogEntry>> fetch({String? search, String? action, int page = 1}) async {
    final data = await _client.getJson('/activity-logs', query: {
      if (search != null && search.isNotEmpty) 'search': search,
      if (action != null && action.isNotEmpty) 'action': action,
      'page': page,
    }) as Map<String, dynamic>;
    return Paginated.fromJson(data, ActivityLogEntry.fromJson);
  }
}
