import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/patient_registration_repository.dart';
import '../domain/lab_registration.dart';
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

/// The registry list screen's page (2026-10-17): the filters plus the
/// archive tab, with the total and `can.archive` the bulk actions need.
typedef PatientRegistrationPageQuery = ({PatientRegistrationFilter filter, bool archived});

final patientRegistrationPageProvider =
    FutureProvider.autoDispose.family<PatientRegistrationPage, PatientRegistrationPageQuery>((ref, query) {
  final f = query.filter;
  return ref.watch(patientRegistrationRepositoryProvider).listPage(
        search: f.search,
        from: f.from,
        to: f.to,
        serviceId: f.serviceId,
        archived: query.archived,
      );
});

/// "المختبر" list (2026-10-17): status tab, search and page.
typedef LabListQuery = ({String status, String? search, int page});

final labListProvider = FutureProvider.autoDispose.family<LabPage, LabListQuery>((ref, query) {
  return ref.watch(patientRegistrationRepositoryProvider).listLab(
        status: query.status,
        search: query.search,
        page: query.page,
      );
});
