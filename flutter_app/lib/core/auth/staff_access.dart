import '../../features/auth/domain/auth_account.dart';

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
    '/records/payments' => const ['super_admin', 'admin', 'editor', 'accountant'].contains(account.role),
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
    '/admin/clinic-settings' || '/admin/waiting-screen-settings' => admin && can('settings'),
    // Services, prices and the lab fee, as on the web's admin menu (2026-10-21).
    '/records/patient-registrations/settings' => admin && can('settings'),
    // A permission since 2026-10-18 (by request), so the lab or the
    // ticket desk can be given the printer without the rest of settings.
    '/admin/printer-settings' => can('printer_settings'),
    // Users management (2026-10-21): the API's own gate.
    '/admin/users' => can('users'),
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
  '/admin/permissions',
  '/admin/department-roles',
  '/admin/activity-log',
  '/admin/backup',
  '/admin/waiting-screen-settings',
  '/admin/broadcast',
];
