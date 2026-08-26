import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';
import '../domain/patient_registration.dart';
import '../domain/register_day.dart';
import '../domain/registration_payment_state.dart';
import '../domain/service.dart';

final patientRegistrationRepositoryProvider = Provider<PatientRegistrationRepository>((ref) {
  return PatientRegistrationRepository(ref.watch(apiClientProvider));
});

/// The reception-desk registration flow — `/register-days` (nested with
/// `services`, for the day-first cascading picker), `/services` (flat, for
/// the settings screen), and `/patient-registrations` (create + list).
/// Settings-screen CRUD (add/delete a day, add/edit/delete a service) is
/// gated `permission:settings,edit` server-side — see
/// `RegisterDayController`/`ServiceController` docblocks for why that
/// reuses an existing permission module instead of a new one.
class PatientRegistrationRepository {
  PatientRegistrationRepository(this._client);
  final ApiClient _client;

  Future<List<RegisterDay>> listDays() async {
    final data = await _client.getJson('/register-days') as List<dynamic>;
    return data.map((e) => RegisterDay.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RegisterDay> createDay(String name) async {
    final data = await _client.postJson('/register-days', body: {'name': name}) as Map<String, dynamic>;
    return RegisterDay.fromJson(data);
  }

  Future<void> deleteDay(int id) => _client.deleteJson('/register-days/$id');

  Future<List<Service>> listServices() async {
    final data = await _client.getJson('/services') as List<dynamic>;
    return data.map((e) => Service.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Service> createService(String name, List<int> dayIds) async {
    final data = await _client.postJson('/services', body: {'name': name, 'day_ids': dayIds}) as Map<String, dynamic>;
    return Service.fromJson(data);
  }

  Future<Service> updateService(int id, String name, List<int> dayIds) async {
    final data =
        await _client.putJson('/services/$id', body: {'name': name, 'day_ids': dayIds}) as Map<String, dynamic>;
    return Service.fromJson(data);
  }

  Future<void> deleteService(int id) => _client.deleteJson('/services/$id');

  /// Day-governed diagnosis ("التشخيص") — see `RegisterDay.taskIds`'s
  /// doc comment and `Api\TaskRegisterDaysController`. Tasks themselves
  /// aren't managed here (see Tasks admin) — this only syncs which days
  /// an existing one is offered on.
  Future<void> updateTaskDays(int taskId, List<int> dayIds) =>
      _client.putJson('/tasks/$taskId/register-days', body: {'day_ids': dayIds});

  Future<Paginated<PatientRegistration>> list({String? search, int? registerDayId, int? serviceId}) async {
    final data = await _client.getJson('/patient-registrations', query: {
      if (search != null && search.isNotEmpty) 'search': search,
      if (registerDayId != null) 'register_day_id': registerDayId,
      if (serviceId != null) 'service_id': serviceId,
    }) as Map<String, dynamic>;
    return Paginated.fromJson(data, PatientRegistration.fromJson);
  }

  Future<PatientRegistration> create({
    required String name,
    required String phone,
    required int registerDayId,
    required int serviceId,
    int? taskId,
  }) async {
    final data = await _client.postJson('/patient-registrations', body: {
      'name': name,
      'phone': phone,
      'register_day_id': registerDayId,
      'service_id': serviceId,
      'task_id': taskId,
    }) as Map<String, dynamic>;
    return PatientRegistration.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// Resolves a scanned desk-payment QR (`{"type":"patient_registration","id":N}`,
  /// see `Api\PatientRegistrationQrController`) to the registration plus
  /// its current payment state.
  Future<RegistrationPaymentState> scan(String payload) async {
    final data = await _client.postJson('/patient-registrations/scan', body: {'payload': payload})
        as Map<String, dynamic>;
    return RegistrationPaymentState.fromJson(data);
  }

  /// Same response shape as [scan] — used to refresh payment state after
  /// taking a payment, without needing to re-scan the ticket.
  Future<RegistrationPaymentState> status(int registrationId) async {
    final data = await _client.getJson('/patient-registrations/$registrationId/status') as Map<String, dynamic>;
    return RegistrationPaymentState.fromJson(data);
  }

  /// Records the lab/reception infectious-disease screening result —
  /// `status` is `'clear'` or `'flagged'`. See `PatientScreeningGate` on
  /// the backend for what this then unblocks (payment, starting a task).
  Future<RegistrationPaymentState> confirmScreening(int registrationId, String status) async {
    final data = await _client.postJson('/patient-registrations/$registrationId/screening', body: {
      'screening_status': status,
    }) as Map<String, dynamic>;
    return RegistrationPaymentState.fromJson(data);
  }

  // Taking the payment itself reuses `RecordsRepository.createPayment()`
  // (`POST /payments`, already generic over its payload) with
  // `patient_registration_id` instead of `appointment_id` — see
  // `Api\PaymentController::validatePayment()` for why exactly one of the
  // two is required. No need for a second near-identical method here.
}
