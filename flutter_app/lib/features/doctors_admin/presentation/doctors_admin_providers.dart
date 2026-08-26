import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/network/paginated.dart';
import '../data/doctors_admin_repository.dart';
import '../domain/doctor_admin.dart';

/// Keyed on `(search, educationTypeId, stageId)` — same record-family
/// shape as `taskAdminListProvider`.
final doctorAdminListProvider = FutureProvider.autoDispose
    .family<Paginated<DoctorAdmin>, ({String? search, int? educationTypeId, int? stageId})>((ref, filter) {
  return ref
      .watch(doctorsAdminRepositoryProvider)
      .list(search: filter.search, educationTypeId: filter.educationTypeId, stageId: filter.stageId);
});

final doctorAdminProvider = FutureProvider.autoDispose.family<DoctorAdmin, int>((ref, id) {
  return ref.watch(doctorsAdminRepositoryProvider).fetch(id);
});

final doctorEducationTypesProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(lookupRepositoryProvider).educationTypes();
});

final doctorStagesProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(lookupRepositoryProvider).stages();
});
