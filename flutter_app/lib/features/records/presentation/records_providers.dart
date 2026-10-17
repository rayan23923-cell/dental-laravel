import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/network/paginated.dart';
import '../data/records_repository.dart';
import '../domain/appointment.dart';
import '../domain/patient.dart';
import '../domain/payment.dart';
import '../domain/payment_stats.dart';

final patientListProvider = FutureProvider.autoDispose.family<Paginated<Patient>, String?>((ref, search) {
  return ref.watch(recordsRepositoryProvider).listPatients(search: search);
});

final patientProvider = FutureProvider.autoDispose.family<Patient, int>((ref, id) {
  return ref.watch(recordsRepositoryProvider).fetchPatient(id);
});

final appointmentListProvider = FutureProvider.autoDispose<Paginated<Appointment>>((ref) {
  return ref.watch(recordsRepositoryProvider).listAppointments();
});

final appointmentProvider = FutureProvider.autoDispose.family<Appointment, int>((ref, id) {
  return ref.watch(recordsRepositoryProvider).fetchAppointment(id);
});

/// Filtering (2026-08-29) — a plain Dart `record` type gets structural
/// (value) equality for free, which is exactly what a Riverpod `family`
/// key needs (so re-requesting the same filters reuses the cached
/// result) — no separate class/`==`/`hashCode` boilerplate needed.
/// `payment_list_screen.dart` was the only call site and is updated to
/// build one of these instead of passing a bare search string.
typedef PaymentFilters = ({String? search, String? from, String? to, String? source});

final paymentListProvider = FutureProvider.autoDispose.family<Paginated<Payment>, PaymentFilters>((ref, filters) {
  return ref.watch(recordsRepositoryProvider).listPayments(
        search: filters.search,
        from: filters.from,
        to: filters.to,
        source: filters.source,
      );
});

/// The income overview above the list (2026-10-17), for the same filters.
final paymentStatsProvider = FutureProvider.autoDispose.family<PaymentStats, PaymentFilters>((ref, filters) {
  return ref.watch(recordsRepositoryProvider).fetchPaymentStats(
        search: filters.search,
        from: filters.from,
        to: filters.to,
        source: filters.source,
      );
});

final paymentProvider = FutureProvider.autoDispose.family<Payment, int>((ref, id) {
  return ref.watch(recordsRepositoryProvider).fetchPayment(id);
});

final stagesLookupProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(lookupRepositoryProvider).stages();
});

final tasksLookupProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(lookupRepositoryProvider).tasks();
});
