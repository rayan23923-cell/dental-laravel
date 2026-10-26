import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/auth_account.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/auth_state.dart';

/// Which app sections a staff account may open (2026-10-18, by request: a
/// lab account with no grants saw every section). Each rule is the server's
/// gate for that section's API, so a hidden section is exactly one that
/// would refuse the account anyway. Keyed by the section's route.
bool staffCanOpen(StaffAccount account, String route) {
  final admin = account.role == 'super_admin' || account.role == 'admin';
  bool can(String module, [String permission = 'view']) => account.can(module, permission);

  return switch (route) {
    '/records/patient-registrations' =>
      const ['super_admin', 'admin', 'editor', 'reception', 'lab'].contains(account.role) && can('patients'),
    '/lab' => const ['super_admin', 'admin', 'editor', 'reception', 'lab'].contains(account.role) &&
        (can('patient_screening') || can('patient_screening', 'confirm')),
    // Payments and the registration services' settings are permissions
    // since 2026-10-24 (by request), the accountant's by default.
    // Since 2026-10-26 also the lab's / ticket desk's own payments.
    '/records/payments' => paymentSources(account)?.isNotEmpty ?? true,
    '/admin/education-types' => admin && can('education_types'),
    '/admin/stages' => admin && can('stages'),
    '/admin/departments' => admin && can('departments'),
    '/admin/tasks' => can('tasks'),
    '/admin/doctors' => can('doctors'),
    '/admin/groups' => admin && can('groups'),
    '/admin/task-progress' => can('task_progress') || can('task_progress', 'view_status'),
    // "إعدادات النماذج" (2026-10-22), opened from task progress.
    '/admin/form-settings' => const ['view', 'view_status', 'form_settings', 'supervisor_code'].any((p) => can('task_progress', p)),
    '/admin/case-sheet-types' => can('case_sheet_types'),
    '/admin/clinic-settings' => admin && can('settings'),
    // The waiting screen's own permission (2026-10-24, by request).
    '/admin/waiting-screen-settings' => can('waiting_screen'),
    '/admin/waiting-screen/pair' => can('waiting_screen', 'pair'),
    // Services, prices and the lab fee, as on the web's admin menu (2026-10-21).
    '/records/patient-registrations/settings' => can('register_settings'),
    // A permission since 2026-10-18 (by request), so the lab or the
    // ticket desk can be given the printer without the rest of settings.
    '/admin/printer-settings' => can('printer_settings'),
    // Users management (2026-10-21): the API's own gate — any admin, since
    // permissions and department roles open from it (2026-10-22).
    '/admin/users' => admin || can('users'),
    '/admin/academic-sessions' ||
    '/admin/permissions' ||
    '/admin/department-roles' ||
    '/admin/activity-log' ||
    '/admin/backup' ||
    '/admin/broadcast' => admin,
    // Pairing a TV is this device's own set-up.
    _ => true,
  };
}

/// The payment sources [account] may see (2026-10-26, by request), the
/// server's `PaymentScope::sources()`: null for every payment, else 'lab'
/// (payments.view_lab) and/or 'registration' (payments.view_tickets). For
/// the report, `view` covers everything only together with `export`.
List<String>? paymentSources(StaffAccount account, {bool report = false}) {
  if (account.can('payments', 'view') && (!report || account.can('payments', 'export'))) return null;
  return [
    if (account.can('payments', 'view_lab')) 'lab',
    if (account.can('payments', 'view_tickets')) 'registration',
  ];
}

/// The signed-in account's [paymentSources] (a doctor or an old server: null).
/// [listen] false reads it once, for callbacks outside `build`.
List<String>? staffPaymentSources(WidgetRef ref, {bool report = false, bool listen = true}) {
  final authState = (listen ? ref.watch(authControllerProvider) : ref.read(authControllerProvider)).valueOrNull;
  final account = authState is Authenticated ? authState.account : null;
  return account is StaffAccount ? paymentSources(account, report: report) : null;
}

/// The payments screen's name for [sources]: the lab's and the ticket
/// desk's own payments are named for what they show.
String paymentsTitleKey(List<String>? sources) => switch (sources) {
      ['lab'] => 'payments.labPaymentsTitle',
      ['registration'] => 'payments.ticketPaymentsTitle',
      _ => 'recordsHub.paymentsTitle',
    };

/// The records and admin hubs' routes, for showing a hub only when
/// something in it can be opened.
const recordsRoutes = ['/records/patient-registrations', '/records/payments'];
const adminRoutes = [
  '/admin/education-types',
  '/admin/stages',
  '/admin/departments',
  '/admin/tasks',
  '/admin/academic-sessions',
  '/admin/doctors',
  '/admin/groups',
  '/admin/task-progress',
  '/admin/case-sheet-types',
  '/admin/clinic-settings',
  '/records/patient-registrations/settings',
  '/admin/users',
  '/admin/activity-log',
  '/admin/backup',
  '/admin/waiting-screen-settings',
  '/admin/waiting-screen/pair',
  '/admin/broadcast',
];

/// Whether the signed-in staff account holds [module].[permission], for the
/// buttons inside a screen (a doctor or an old server: true, as `can` does).
bool staffCan(WidgetRef ref, String module, String permission) {
  final authState = ref.watch(authControllerProvider).valueOrNull;
  final account = authState is Authenticated ? authState.account : null;
  return account is! StaffAccount || account.can(module, permission);
}
