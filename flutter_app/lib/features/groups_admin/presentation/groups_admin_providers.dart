import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lookup_repository.dart';
import '../data/groups_admin_repository.dart';
import '../domain/group_admin.dart';

/// Keyed on `(search, stageId, doctorId)` — same record-family shape as
/// `taskAdminListProvider`/`doctorAdminListProvider`. `doctorId` is the
/// NFC-scan case ("which group is this doctor in") — combinable with the
/// other two, same as everything else in this admin app's filter bars.
final groupListProvider = FutureProvider.autoDispose
    .family<List<GroupAdmin>, ({String? search, int? stageId, int? doctorId})>((ref, filter) {
  return ref
      .watch(groupsAdminRepositoryProvider)
      .list(search: filter.search, stageId: filter.stageId, doctorId: filter.doctorId);
});

final groupProvider = FutureProvider.autoDispose.family<GroupAdmin, int>((ref, id) {
  return ref.watch(groupsAdminRepositoryProvider).fetch(id);
});

final groupStagesProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(lookupRepositoryProvider).stages();
});

/// UI-only — `Group` has no `education_type_id` column. Used purely to
/// narrow the stage dropdown on the list/form screens, same as
/// `task_form_screen.dart` does for `Task` (which also lacks the column).
final groupEducationTypesProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(lookupRepositoryProvider).educationTypes();
});

final availableDoctorsProvider = FutureProvider.autoDispose.family<List<AvailableDoctor>, int?>((ref, stageId) {
  return ref.watch(groupsAdminRepositoryProvider).availableDoctors(stageId: stageId);
});
