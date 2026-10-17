import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';
import '../domain/appointment.dart';
import '../domain/patient.dart';
import '../domain/payment.dart';
import '../domain/payment_stats.dart';

final recordsRepositoryProvider = Provider<RecordsRepository>((ref) {
  return RecordsRepository(ref.watch(apiClientProvider));
});

/// CRUD for the staff-only "front desk" trio — patients, appointments,
/// payments. All three REST resources share the same `{data: {...}}` /
/// paginated envelope as the case-sheet resources, so this mirrors
/// `CaseSheetRecordRepository`'s shape rather than reinventing one. The
/// `/stages`/`/tasks` dropdown lookups these forms need live in
/// `core/data/lookup_repository.dart` now, shared with the other
/// features that need the same reference data.
class RecordsRepository {
  RecordsRepository(this._client);
  final ApiClient _client;

  // Patients
  Future<Paginated<Patient>> listPatients({String? search}) async {
    final data = await _client.getJson('/patients', query: {if (search != null && search.isNotEmpty) 'search': search})
        as Map<String, dynamic>;
    return Paginated.fromJson(data, Patient.fromJson);
  }

  Future<Patient> fetchPatient(int id) async {
    final data = await _client.getJson('/patients/$id') as Map<String, dynamic>;
    return Patient.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<Patient> createPatient(Map<String, dynamic> payload) async {
    final data = await _client.postJson('/patients', body: payload) as Map<String, dynamic>;
    return Patient.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<Patient> updatePatient(int id, Map<String, dynamic> payload) async {
    final data = await _client.putJson('/patients/$id', body: payload) as Map<String, dynamic>;
    return Patient.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<void> deletePatient(int id) => _client.deleteJson('/patients/$id');

  // Appointments
  Future<Paginated<Appointment>> listAppointments() async {
    final data = await _client.getJson('/appointments') as Map<String, dynamic>;
    return Paginated.fromJson(data, Appointment.fromJson);
  }

  Future<Appointment> fetchAppointment(int id) async {
    final data = await _client.getJson('/appointments/$id') as Map<String, dynamic>;
    return Appointment.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<Appointment> createAppointment(Map<String, dynamic> payload) async {
    final data = await _client.postJson('/appointments', body: payload) as Map<String, dynamic>;
    return Appointment.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<Appointment> updateAppointment(int id, Map<String, dynamic> payload) async {
    final data = await _client.putJson('/appointments/$id', body: payload) as Map<String, dynamic>;
    return Appointment.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteAppointment(int id) => _client.deleteJson('/appointments/$id');

  // Payments
  /// Filtering (2026-08-29) — date range on `paid_at` (the only date this
  /// table has) and which of the two mutually-exclusive sources a payment
  /// settled; see `Api\PaymentController::index()`'s matching comment for
  /// why no doctor or paid/unpaid filter exists.
  Future<Paginated<Payment>> listPayments({String? search, String? from, String? to, String? source}) async {
    final data = await _client.getJson('/payments', query: {
      if (search != null && search.isNotEmpty) 'search': search,
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (source != null && source.isNotEmpty) 'source': source,
    }) as Map<String, dynamic>;
    return Paginated.fromJson(data, Payment.fromJson);
  }

  Future<Payment> fetchPayment(int id) async {
    final data = await _client.getJson('/payments/$id') as Map<String, dynamic>;
    return Payment.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<Payment> createPayment(Map<String, dynamic> payload) async {
    final data = await _client.postJson('/payments', body: payload) as Map<String, dynamic>;
    return Payment.fromJson(data['data'] as Map<String, dynamic>);
  }

  // No `updatePayment()` (2026-10-17): payments aren't edited by hand any
  // more, and the API no longer routes `PUT /payments/{id}`.

  /// Income overview for the same filters as [listPayments] (2026-10-17).
  Future<PaymentStats> fetchPaymentStats({String? search, String? from, String? to, String? source}) async {
    final data = await _client.getJson('/payments/stats', query: {
      if (search != null && search.isNotEmpty) 'search': search,
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (source != null && source.isNotEmpty) 'source': source,
    }) as Map<String, dynamic>;
    return PaymentStats.fromJson(data);
  }

  Future<void> deletePayment(int id) => _client.deleteJson('/payments/$id');

  /// Every payment for the same filters as [listPayments], with the
  /// overview — the payments report PDF's data (2026-10-17).
  Future<PaymentReport> fetchPaymentReport({String? search, String? from, String? to, String? source}) async {
    final data = await _client.getJson('/payments/report', query: {
      if (search != null && search.isNotEmpty) 'search': search,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (source != null) 'source': source,
    }) as Map<String, dynamic>;
    return PaymentReport.fromJson(data);
  }
}
