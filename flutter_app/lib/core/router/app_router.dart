import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart' show GlobalKey, NavigatorState;
import 'package:go_router/go_router.dart';

import '../../features/academic_sessions_admin/presentation/academic_session_detail_screen.dart';
import '../../features/academic_sessions_admin/presentation/academic_session_form_screen.dart';
import '../../features/academic_sessions_admin/presentation/academic_session_list_screen.dart';
import '../../features/admin/presentation/admin_hub_screen.dart';
import '../../features/admin_broadcast/presentation/admin_broadcast_screen.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/auth_state.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/case_sheet_forms/presentation/case_sheet_form_screen.dart';
import '../../features/activity_log/presentation/activity_log_list_screen.dart';
import '../../features/backup_admin/presentation/backup_screen.dart';
import '../../features/case_sheet_types_admin/presentation/case_sheet_type_list_screen.dart';
import '../../features/clinic_settings_admin/presentation/clinic_settings_edit_screen.dart';
import '../../features/department_roles_admin/presentation/department_roles_screen.dart';
import '../../features/patient_registration/domain/registration_payment_state.dart';
import '../../features/patient_registration/presentation/lab_list_screen.dart';
import '../../features/patient_registration/presentation/patient_registration_form_screen.dart';
import '../../features/patient_registration/presentation/patient_registration_list_screen.dart';
import '../../features/patient_registration/presentation/patient_registration_payment_screen.dart';
import '../../features/patient_registration/presentation/patient_registration_screening_screen.dart';
import '../../features/patient_registration/presentation/register_settings_screen.dart';
import '../../features/permissions_admin/presentation/permission_edit_screen.dart';
import '../../features/permissions_admin/presentation/permission_user_list_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/sessions/presentation/sessions_screen.dart';
import '../../features/users_admin/presentation/user_edit_screen.dart';
import '../../features/users_admin/presentation/user_form_screen.dart';
import '../../features/users_admin/presentation/user_list_screen.dart';
import '../../features/case_sheet_forms/presentation/case_sheet_record_list_screen.dart';
import '../../features/case_sheet_forms/presentation/case_sheet_types_screen.dart';
import '../../features/doctors_admin/presentation/doctor_form_screen.dart';
import '../../features/doctors_admin/presentation/doctor_import_screen.dart';
import '../../features/doctors_admin/presentation/doctor_list_screen.dart';
import '../../features/printing/presentation/printer_settings_screen.dart';
import '../../features/task_progress_admin/presentation/doctor_progress_screen.dart';
import '../../features/task_progress_admin/presentation/task_progress_screen.dart';
import '../../features/form_settings/presentation/form_settings_screen.dart';
import '../../features/groups_admin/presentation/group_detail_screen.dart';
import '../../features/groups_admin/presentation/group_form_screen.dart';
import '../../features/groups_admin/presentation/group_list_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/notifications/presentation/notification_inbox_screen.dart';
import '../../features/records/presentation/appointments/appointment_form_screen.dart';
import '../../features/records/presentation/appointments/appointment_list_screen.dart';
import '../../features/records/presentation/patients/patient_form_screen.dart';
import '../../features/records/presentation/patients/patient_list_screen.dart';
import '../../features/records/presentation/payments/payment_form_screen.dart';
import '../../features/records/presentation/payments/payment_list_screen.dart';
import '../../features/records/presentation/records_hub_screen.dart';
import '../../features/task_instances/presentation/qr_scan_screen.dart';
import '../../features/task_instances/presentation/task_instance_detail_screen.dart';
import '../../features/tasks_admin/presentation/task_detail_screen.dart';
import '../../features/tasks_admin/presentation/task_form_screen.dart';
import '../../features/tasks_admin/presentation/task_list_screen.dart';
import '../../features/taxonomy_admin/domain/taxonomy_item.dart';
import '../../features/taxonomy_admin/presentation/taxonomy_list_screen.dart';
import '../../features/waiting_screen_admin/presentation/waiting_screen_pair_screen.dart';
import '../../features/waiting_screen_admin/presentation/waiting_screen_settings_screen.dart';
import '../config/server_settings_screen.dart';
import '../widgets/app_shell.dart';
import '../../features/notifications/presentation/notification_alerts.dart';

/// Bridges Riverpod's `authControllerProvider` to go_router's
/// `refreshListenable` — the mechanism that re-evaluates `redirect()`
/// *without* rebuilding the `GoRouter` instance itself.
///
/// This exists because a `Provider` that simply `watch`es
/// `authControllerProvider` and returns a new `GoRouter` — the
/// simpler-looking approach — recreates the whole router (and therefore
/// every screen it holds) on every auth-state change.
/// Confirmed as a real bug during verification, not just a theoretical
/// concern: a failed login (`AuthController` transitioning
/// Unauthenticated -> loading -> error) destroyed `LoginScreen`'s own
/// `State` mid-flight, wiping both the just-typed credentials and the
/// inline validation error the screen was about to show — the one path
/// where the router rebuilding was most visible, since it happens on
/// every single failed login attempt, not just on rarer full
/// login/logout transitions.
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(Ref ref) {
    ref.listen(authControllerProvider, (previous, next) => notifyListeners());
  }
}

/// The app's root navigator, for dialogs shown from above the router
/// (the update check in `DesktopUpdateGate`).
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _AuthRefreshListenable(ref);
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refreshListenable,
    routes: [
      // "Outside" routes — full-screen, no persistent sidebar: splash/login,
      // plus every form/detail/scan screen (a focused single-record task
      // doesn't need 280px of nav chrome eating its width). Declared before
      // the ShellRoute below on purpose — see the `/case-sheets/scan-patient`
      // comment further down for why the relative order still matters even
      // though these are no longer textually adjacent to `/case-sheets/:resource`.
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      // Cloud or clinic server — reachable before login (from the login
      // screen) as well as from the profile page.
      GoRoute(path: '/server', builder: (context, state) => const ServerSettingsScreen()),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/sessions',
        builder: (context, state) => const SessionsScreen(),
      ),
      GoRoute(
        path: '/tasks/:id',
        builder: (context, state) => TaskInstanceDetailScreen(
          taskInstanceId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(path: '/scan', builder: (context, state) => const QrScanScreen()),
      // Must be registered before the ShellRoute's own `/case-sheets/:resource`
      // below — go_router matches routes in overall declaration order, so a
      // `:resource` route reached first would otherwise swallow this static
      // path, capturing `resource: 'scan-patient'` and routing to the
      // record-list screen instead (a real bug found live: the scan button
      // opened a blank "scan-patient" list that then failed fetching a
      // nonexistent API resource). Sidebar-shell split (this revision) moved
      // `/case-sheets/:resource` inside the ShellRoute below since it's a
      // list screen, while this one stays outside (it's a full-screen camera
      // flow) — no longer textually adjacent, so this comment is the only
      // thing preserving the ordering rule; do not reorder either route
      // without re-checking `/case-sheets/scan-patient` still resolves to
      // QrScanScreen, not CaseSheetRecordListScreen.
      GoRoute(
        path: '/case-sheets/scan-patient',
        builder: (context, state) =>
            const QrScanScreen(mode: QrScanMode.caseSheetPatientAutofill),
      ),
      GoRoute(
        path: '/case-sheets/:resource/new',
        builder: (context, state) => CaseSheetFormScreen(
          resource: state.pathParameters['resource']!,
          recordId: null,
          taskInstanceId: _intQueryParam(state, 'task_instances_id'),
          taskId: _intQueryParam(state, 'task_id'),
          readonly: state.uri.queryParameters['readonly'] == '1',
          supervisorEditableFields: _listQueryParam(state, 'supervisor_fields'),
        ),
      ),
      GoRoute(
        path: '/case-sheets/:resource/:id',
        builder: (context, state) => CaseSheetFormScreen(
          resource: state.pathParameters['resource']!,
          recordId: int.parse(state.pathParameters['id']!),
          taskInstanceId: _intQueryParam(state, 'task_instances_id'),
          taskId: _intQueryParam(state, 'task_id'),
          readonly: state.uri.queryParameters['readonly'] == '1',
          supervisorEditableFields: _listQueryParam(state, 'supervisor_fields'),
        ),
      ),
      GoRoute(
        path: '/records/patients/new',
        builder: (context, state) => const PatientFormScreen(),
      ),
      GoRoute(
        path: '/records/patients/:id',
        builder: (context, state) => PatientFormScreen(
          patientId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/records/appointments/new',
        builder: (context, state) => const AppointmentFormScreen(),
      ),
      GoRoute(
        path: '/records/appointments/:id',
        builder: (context, state) => AppointmentFormScreen(
          appointmentId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/records/patient-registrations/new',
        builder: (context, state) => const PatientRegistrationFormScreen(),
      ),
      GoRoute(
        path: '/records/patient-registrations/settings',
        builder: (context, state) => const RegisterSettingsScreen(),
      ),
      GoRoute(
        path: '/records/patient-registrations/scan',
        builder: (context, state) =>
            const QrScanScreen(mode: QrScanMode.patientRegistrationPayment),
      ),
      GoRoute(
        path: '/records/patient-registrations/payment',
        builder: (context, state) => PatientRegistrationPaymentScreen(
          initial: state.extra! as RegistrationPaymentState,
        ),
      ),
      // Infectious-disease screening gate (2026-08-26) — mirrors the
      // scan/payment route pair immediately above.
      // The lab list (2026-10-17, the web /lab page). The old scanner
      // path, which the dashboard's lab shortcut still opens, now leads
      // here; scanning stays one tap away on the list (/lab/scan).
      GoRoute(
        path: '/records/patient-registrations/scan-screening',
        redirect: (context, state) => '/lab',
      ),
      GoRoute(
        path: '/lab',
        builder: (context, state) => const LabListScreen(),
      ),
      // Outside the shell (2026-10-18): it is opened from screens above the
      // shell (the lab, the print-error "إعدادات الطابعة" button), and
      // pushing a shell route from there built a second shell and failed
      // (go_router "keyReservation" assertion), so the screen never opened.
      GoRoute(
        path: '/admin/printer-settings',
        builder: (context, state) => const PrinterSettingsScreen(),
      ),
      GoRoute(
        path: '/lab/scan',
        builder: (context, state) =>
            const QrScanScreen(mode: QrScanMode.patientRegistrationScreening),
      ),
      GoRoute(
        path: '/records/patient-registrations/screening',
        builder: (context, state) => PatientRegistrationScreeningScreen(
          initial: state.extra! as RegistrationPaymentState,
        ),
      ),
      GoRoute(
        path: '/records/patient-registrations/scan-for-task',
        builder: (context, state) =>
            const QrScanScreen(mode: QrScanMode.taskPatientLink),
      ),
      GoRoute(
        path: '/records/patient-registrations/scan-for-payment',
        builder: (context, state) =>
            const QrScanScreen(mode: QrScanMode.paymentPatientLink),
      ),
      GoRoute(
        path: '/records/payments/:id',
        builder: (context, state) => PaymentFormScreen(
          paymentId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/admin/doctors/new',
        builder: (context, state) => const DoctorFormScreen(),
      ),
      // Excel import (2026-10-17), the web's doctors.import.show — before
      // `/admin/doctors/:id`, which would otherwise take "import" as an id.
      GoRoute(
        path: '/admin/doctors/import',
        builder: (context, state) => const DoctorImportScreen(),
      ),
      // A doctor's progress (2026-10-17) — what their ID card QR opens
      // from the task-progress scanner, like the web's doctors.progress.
      GoRoute(
        path: '/admin/doctors/:id/progress',
        builder: (context, state) =>
            DoctorProgressScreen(doctorId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/admin/doctors/:id',
        builder: (context, state) =>
            DoctorFormScreen(doctorId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/admin/groups/new',
        builder: (context, state) => const GroupFormScreen(),
      ),
      GoRoute(
        path: '/admin/groups/:id/edit',
        builder: (context, state) =>
            GroupFormScreen(groupId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/admin/groups/:id',
        builder: (context, state) =>
            GroupDetailScreen(groupId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/admin/tasks/new',
        // Carries the list screen's current filter over (see
        // TaskListScreen's FAB) — extra is null when navigated to any
        // other way, in which case the form opens empty as before.
        builder: (context, state) {
          final extra = state.extra as Map<String, int?>?;
          return TaskFormScreen(
            initialStageId: extra?['stageId'],
            initialEducationTypeId: extra?['educationTypeId'],
          );
        },
      ),
      // The task and its instances (2026-10-17), the web's Tasks/Show.
      GoRoute(
        path: '/admin/tasks/:id/detail',
        builder: (context, state) =>
            TaskDetailScreen(taskId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/admin/tasks/:id',
        builder: (context, state) =>
            TaskFormScreen(taskId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/admin/academic-sessions/new',
        builder: (context, state) => const AcademicSessionFormScreen(),
      ),
      GoRoute(
        path: '/admin/academic-sessions/:id/edit',
        builder: (context, state) => AcademicSessionFormScreen(
          sessionId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/admin/academic-sessions/:id',
        builder: (context, state) => AcademicSessionDetailScreen(
          sessionId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/admin/users/new',
        builder: (context, state) => const UserFormScreen(),
      ),
      GoRoute(
        path: '/admin/users/:id',
        builder: (context, state) => UserEditScreen(userId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/admin/permissions/:id',
        builder: (context, state) => PermissionEditScreen(
          userId: int.parse(state.pathParameters['id']!),
        ),
      ),

      // "Inside" routes — hub/list/settings screens, wrapped in the
      // persistent sidebar (by request: "سايد بار مشابه لواجهة chatgbt").
      // See `AppShell`'s own doc comment: it's a plain Row/Stack, not a
      // Scaffold, so none of these screens' own Scaffold/AppBar needed to
      // change for this wrap.
      ShellRoute(
        builder: (context, state, child) => AppShell(child: NotificationAlerts(child: child)),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationInboxScreen(),
          ),
          // "رموز المهام المعلقة" was removed (2026-10-15, by request): each
          // slot's QR is on "مهامي", so the old path lands there.
          GoRoute(
            path: '/pending-tasks-qr',
            redirect: (context, state) => '/home',
          ),
          GoRoute(
            path: '/case-sheets',
            builder: (context, state) => const CaseSheetTypesScreen(),
          ),
          GoRoute(
            path: '/case-sheets/:resource',
            builder: (context, state) => CaseSheetRecordListScreen(
              resource: state.pathParameters['resource']!,
            ),
          ),
          GoRoute(
            path: '/records',
            builder: (context, state) => const RecordsHubScreen(),
          ),
          GoRoute(
            path: '/records/patients',
            builder: (context, state) => const PatientListScreen(),
          ),
          GoRoute(
            path: '/records/appointments',
            builder: (context, state) => const AppointmentListScreen(),
          ),
          GoRoute(
            path: '/records/patient-registrations',
            builder: (context, state) => const PatientRegistrationListScreen(),
          ),
          GoRoute(
            path: '/records/payments',
            builder: (context, state) => const PaymentListScreen(),
          ),
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminHubScreen(),
          ),
          GoRoute(
            path: '/admin/doctors',
            builder: (context, state) => const DoctorListScreen(),
          ),
          GoRoute(
            path: '/admin/groups',
            builder: (context, state) => const GroupListScreen(),
          ),
          GoRoute(
            path: '/admin/tasks',
            builder: (context, state) => const TaskListScreen(),
          ),
          GoRoute(
            path: '/admin/education-types',
            builder: (context, state) =>
                const TaxonomyListScreen(kind: TaxonomyKind.educationType),
          ),
          GoRoute(
            path: '/admin/stages',
            builder: (context, state) =>
                const TaxonomyListScreen(kind: TaxonomyKind.stage),
          ),
          GoRoute(
            path: '/admin/departments',
            builder: (context, state) =>
                const TaxonomyListScreen(kind: TaxonomyKind.department),
          ),
          GoRoute(
            path: '/admin/academic-sessions',
            builder: (context, state) => const AcademicSessionListScreen(),
          ),
          GoRoute(
            path: '/admin/case-sheet-types',
            builder: (context, state) => const CaseSheetTypeListScreen(),
          ),
          // Users management (2026-10-21, by request).
          GoRoute(
            path: '/admin/users',
            builder: (context, state) => const UserListScreen(),
          ),
          GoRoute(
            path: '/admin/permissions',
            builder: (context, state) => const PermissionUserListScreen(),
          ),
          GoRoute(
            path: '/admin/task-progress',
            builder: (context, state) => TaskProgressScreen(initialTab: state.uri.queryParameters['tab'] ?? 'progress'),
          ),
          // "إعدادات النماذج" and the supervisor code (2026-10-22).
          GoRoute(
            path: '/admin/form-settings',
            builder: (context, state) => const FormSettingsScreen(),
          ),
          GoRoute(
            path: '/admin/clinic-settings',
            builder: (context, state) => const ClinicSettingsEditScreen(),
          ),
          GoRoute(
            path: '/admin/activity-log',
            builder: (context, state) => const ActivityLogListScreen(),
          ),
          GoRoute(
            path: '/admin/backup',
            builder: (context, state) => const BackupScreen(),
          ),
          // Ported from the web's admin pages (2026-10-17).
          GoRoute(
            path: '/admin/waiting-screen-settings',
            builder: (context, state) => const WaitingScreenSettingsScreen(),
          ),
          GoRoute(
            path: '/admin/waiting-screen/pair',
            builder: (context, state) => const WaitingScreenPairScreen(),
          ),
          GoRoute(
            path: '/admin/department-roles',
            builder: (context, state) => const DepartmentRolesScreen(),
          ),
          GoRoute(
            path: '/admin/broadcast',
            builder: (context, state) => const AdminBroadcastScreen(),
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      // `read`, not `watch` — this provider must not itself depend on
      // authControllerProvider (see the class doc above); `redirect` is
      // re-invoked by go_router whenever `refreshListenable` fires.
      final authState = ref.read(authControllerProvider);
      final loggingIn = state.matchedLocation == '/login';
      final onSplash = state.matchedLocation == '/splash';
      final onServer = state.matchedLocation == '/server';

      return authState.when(
        // Covers both the initial session-restore loading (before the
        // very first `build()` resolves — the `/splash` case) and a
        // login-attempt in flight (the user is on `/login`, submitting;
        // `AuthController.login` sets `AsyncLoading()`
        // again, which must NOT bounce them off the form they're
        // filling in — the login screen's own spinner already reflects
        // this state). Any other location seeing `loading` (shouldn't
        // normally happen) falls back to `/splash`.
        loading: () => (onSplash || loggingIn || onServer) ? null : '/splash',
        error: (error, stackTrace) => (loggingIn || onServer) ? null : '/login',
        data: (authState) => switch (authState) {
          Unauthenticated() => (loggingIn || onServer) ? null : '/login',
          Authenticated() => (loggingIn || onSplash) ? '/home' : null,
        },
      );
    },
  );
});

int? _intQueryParam(GoRouterState state, String name) {
  final raw = state.uri.queryParameters[name];
  return raw == null ? null : int.tryParse(raw);
}

/// Carries the staff supervisor-preview state (2026-08-28) across
/// navigation, since `CaseSheetFormScreen` is reached by pushing a plain
/// URL rather than passing a widget's constructor args directly — mirrors
/// `task_instances_id`/`task_id` above. Comma-separated field-key list;
/// field keys are plain identifiers (see `App\Support\
/// CaseSheetSupervisorFields`), so no escaping is needed.
List<String> _listQueryParam(GoRouterState state, String name) {
  final raw = state.uri.queryParameters[name];
  return (raw == null || raw.isEmpty) ? const [] : raw.split(',');
}
