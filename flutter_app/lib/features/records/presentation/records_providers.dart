import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/network/paginated.dart';
import '../data/records_repository.dart';
import '../domain/appointment.dart';
import '../domain/patient.dart';
import '../domain/payment.dart';

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

final paymentListProvider = FutureProvider.autoDispose.family<Paginated<Payment>, String?>((ref, search) {
  return ref.watch(recordsRepositoryProvider).listPayments(search: search);
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
