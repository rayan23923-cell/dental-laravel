import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/patient_registration_repository.dart';
import '../domain/patient_registration.dart';
import '../domain/register_day.dart';
import '../domain/service.dart';

final registerDaysProvider = FutureProvider.autoDispose<List<RegisterDay>>((ref) {
  return ref.watch(patientRegistrationRepositoryProvider).listDays();
});

final servicesProvider = FutureProvider.autoDispose<List<Service>>((ref) {
  return ref.watch(patientRegistrationRepositoryProvider).listServices();
});

/// Search + day/service filters together — grown from a bare `String?`
/// (search-only) once the list screen needed day/service narrowing too.
/// A record (not a class) is enough: it gets `==`/`hashCode` for free,
/// which is what makes this usable as a Riverpod family key.
/// `from`/`to` (yyyy-MM-dd) replaced the register-day filter (2026-10-14,
/// by request): a date range like the payments list.
typedef PatientRegistrationFilter = ({String? search, String? from, String? to, int? serviceId});

const _noFilter = (search: null, from: null, to: null, serviceId: null);

final patientRegistrationListProvider =
    FutureProvider.autoDispose.family<List<PatientRegistration>, PatientRegistrationFilter?>((ref, filter) async {
  final f = filter ?? _noFilter;
  final page = await ref.watch(patientRegistrationRepositoryProvider).list(
        search: f.search,
        from: f.from,
        to: f.to,
        serviceId: f.serviceId,
      );
  return page.items;
});
