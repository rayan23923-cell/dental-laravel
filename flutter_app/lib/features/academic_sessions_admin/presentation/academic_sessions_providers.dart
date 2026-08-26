import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/academic_sessions_repository.dart';
import '../domain/academic_session_admin.dart';

final academicSessionListProvider = FutureProvider.autoDispose<List<AcademicSessionAdmin>>((ref) {
  return ref.watch(academicSessionsRepositoryProvider).list();
});

final academicSessionDetailProvider = FutureProvider.autoDispose.family<AcademicSessionDetail, int>((ref, id) {
  return ref.watch(academicSessionsRepositoryProvider).fetch(id);
});

/// The active academic year, shared app-wide — deliberately not
/// `.autoDispose` (same reasoning as `clinicSettingsProvider`): it's read
/// by five different screens (dashboard + Doctors/Groups/Tasks/Task-
/// Progress banners), and disposing/refetching every time one of them
/// unmounts would be wasteful. Callers that change which year is active
/// (`setCurrent()` above) should `ref.invalidate(currentAcademicYearProvider)`.
final currentAcademicYearProvider = FutureProvider<CurrentAcademicYear?>((ref) {
  return ref.watch(academicSessionsRepositoryProvider).current();
});
