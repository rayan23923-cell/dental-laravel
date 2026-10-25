import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginated.dart';
import '../domain/lab_registration.dart';
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

  /// `price` (2026-10-12) is optional server-side; `dayIds` too now that
  /// registration no longer asks for a day. Note the server keeps the old
  /// price when an update sends `price: null`, so a price can be changed
  /// but not cleared from here.
  Future<Service> createService(String name, {double? price, double? studentDiscountPercent, List<int>? dayIds}) async {
    final data = await _client.postJson('/services', body: {
      'name': name,
      'price': price,
      if (studentDiscountPercent != null) 'student_discount_percent': studentDiscountPercent,
      if (dayIds != null) 'day_ids': dayIds,
    }) as Map<String, dynamic>;
    return Service.fromJson(data);
  }

  /// The server syncs a missing `day_ids` to "no days", so the settings
  /// screen passes the service's current days through to keep them.
  Future<Service> updateService(int id, String name, {double? price, double? studentDiscountPercent, List<int>? dayIds}) async {
    final data = await _client.putJson('/services/$id', body: {
      'name': name,
      'price': price,
      if (studentDiscountPercent != null) 'student_discount_percent': studentDiscountPercent,
      if (dayIds != null) 'day_ids': dayIds,
    }) as Map<String, dynamic>;
    return Service.fromJson(data);
  }

  Future<void> deleteService(int id) => _client.deleteJson('/services/$id');

  /// Day-governed diagnosis ("التشخيص") — see `RegisterDay.taskIds`'s
  /// doc comment and `Api\TaskRegisterDaysController`. Tasks themselves
  /// aren't managed here (see Tasks admin) — this only syncs which days
  /// an existing one is offered on.
  Future<void> updateTaskDays(int taskId, List<int> dayIds) =>
      _client.putJson('/tasks/$taskId/register-days', body: {'day_ids': dayIds});

  /// A fingerprint of the registrations that changes whenever one is
  /// added, edited, screened or paid (2026-10-19); see
  /// `RegistrationsStampController`. null from servers without it.
  Future<String?> stamp() async {
    final data = await _client.getJson('/patient-registrations-stamp') as Map<String, dynamic>;
    return data['stamp'] as String?;
  }

  Future<Paginated<PatientRegistration>> list({String? search, String? from, String? to, int? serviceId}) async =>
      (await listPage(search: search, from: from, to: to, serviceId: serviceId)).page;

  /// [list] plus the archive tab (`archived: true` lists the archived
  /// registrations, 2026-10-17, as the web registry's) and whether this
  /// account may archive/restore (`can.archive`, i.e. `patients,delete`).
  Future<PatientRegistrationPage> listPage({
    String? search,
    String? from,
    String? to,
    int? serviceId,
    bool archived = false,
  }) async {
    final data = await _client.getJson('/patient-registrations', query: {
      ..._filterQuery(search: search, from: from, to: to, serviceId: serviceId),
      if (archived) 'archived': 1,
    }) as Map<String, dynamic>;
    return PatientRegistrationPage(
      page: Paginated.fromJson(data, PatientRegistration.fromJson),
      canArchive: (data['can'] as Map<String, dynamic>?)?['archive'] as bool? ?? false,
    );
  }

  static Map<String, dynamic> _filterQuery({String? search, String? from, String? to, int? serviceId}) => {
        if (search != null && search.isNotEmpty) 'search': search,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        if (serviceId != null) 'service_id': serviceId,
      };

  /// Bulk archive (soft delete — payments are kept), the web
  /// `destroy-many`.
  Future<void> archiveMany(List<int> ids) =>
      _client.deleteJson('/patient-registrations-bulk', body: {'ids': ids});

  /// Archives every registration matching the filters ("أرشفة الكل").
  Future<void> archiveAll({String? search, String? from, String? to, int? serviceId}) =>
      _client.deleteJson('/patient-registrations-bulk', body: {
        'all': true,
        ..._filterQuery(search: search, from: from, to: to, serviceId: serviceId),
      });

  /// Brings archived registrations back, the web `restore-many`.
  Future<void> restoreMany(List<int> ids) =>
      _client.postJson('/patient-registrations-restore', body: {'ids': ids});

  /// "المختبر" list (2026-10-17, the web `/lab` page): by screening
  /// status ('pending' | 'flagged' | 'clear' | 'all') and name/phone.
  Future<LabPage> listLab({String status = 'pending', String? search, int page = 1}) async {
    final data = await _client.getJson('/lab', query: {
      'status': status,
      if (search != null && search.isNotEmpty) 'search': search,
      if (page > 1) 'page': page,
    }) as Map<String, dynamic>;
    return LabPage.fromJson(data);
  }

  /// [scan] for the lab: gated by the screening permission instead of
  /// `patients,view`, so the `lab` role can scan tickets too.
  Future<RegistrationPaymentState> labScan(String payload) async {
    final data = await _client.postJson('/lab/scan', body: {'payload': payload}) as Map<String, dynamic>;
    return RegistrationPaymentState.fromJson(data);
  }

  /// [status] for the lab, same gate as [labScan].
  Future<RegistrationPaymentState> labStatus(int registrationId) async {
    final data = await _client.getJson('/lab/$registrationId') as Map<String, dynamic>;
    return RegistrationPaymentState.fromJson(data);
  }

  /// The ticket QR image path for lab slips (lab-gated twin of
  /// `/patient-registrations/{id}/qr`).
  static String labQrPath(int registrationId) => '/lab/$registrationId/qr';

  Future<PatientRegistration> create({
    required String name,
    required String phone,
    required int serviceId,
    int? taskId,
    bool discountEligible = false,
  }) async {
    // No `register_day_id` since 2026-10-12 — registration is by service
    // only (the server column is nullable now). No amount either: the
    // server charges the service's price.
    final data = await _client.postJson('/patient-registrations', body: {
      'name': name,
      'phone': phone,
      'service_id': serviceId,
      'task_id': taskId,
      // Student discount (2026-10-25): the server takes the price less the
      // service's percentage when true.
      'discount_eligible': discountEligible,
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

  /// Doctor-only twin of [scan], for the case-sheet "مسح رمز المريض"
  /// patient-autofill button (2026-08-28) — [scan] hits a
  /// `permission:patients,view`-gated route that rejects any Doctor
  /// principal outright, so a doctor's own scan attempt always 403'd
  /// ("لا تملك صلاحية لهذا الإجراء", found live on a real device). Same
  /// response shape — also enforces `PatientScreeningGate` server-side,
  /// so a not-yet-screened-clear patient surfaces as a normal caught
  /// error here instead of a silent success.
  Future<RegistrationPaymentState> scanForCaseSheet(String payload) async {
    final data = await _client.postJson('/patient-registrations/scan-for-case-sheet', body: {'payload': payload})
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

  /// Marks the registration clear by reusing the patient's still-valid
  /// earlier clear result (`RegistrationPaymentState.previousScreening`,
  /// 2026-10-12) — no new test, no lab fee. 422s when there is none.
  Future<RegistrationPaymentState> reuseScreening(int registrationId) async {
    final data = await _client.postJson('/patient-registrations/$registrationId/screening/reuse')
        as Map<String, dynamic>;
    return RegistrationPaymentState.fromJson(data);
  }

  // Taking the payment itself reuses `RecordsRepository.createPayment()`
  // (`POST /payments`, already generic over its payload) with
  // `patient_registration_id` instead of `appointment_id` — see
  // `Api\PaymentController::validatePayment()` for why exactly one of the
  // two is required. No need for a second near-identical method here.
}

/// One page of the registry plus whether this account may archive.
class PatientRegistrationPage {
  const PatientRegistrationPage({required this.page, required this.canArchive});

  final Paginated<PatientRegistration> page;
  final bool canArchive;
}
