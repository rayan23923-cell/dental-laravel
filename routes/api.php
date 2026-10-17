<?php

use App\Http\Controllers\Api\AcademicSessionController;
use App\Http\Controllers\Api\ActivityLogController;
use App\Http\Controllers\Api\AppointmentController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BackupController;
use App\Http\Controllers\Api\BrandingController;
use App\Http\Controllers\Api\DesktopReleaseController;
use App\Http\Controllers\Api\CaseSheetFormController;
use App\Http\Controllers\Api\CaseSheetPrintController;
use App\Http\Controllers\Api\CaseSheetTypeController;
use App\Http\Controllers\Api\ClinicSettingController;
use App\Http\Controllers\Api\CompleteDentureRecordController;
use App\Http\Controllers\Api\DentalChartController;
use App\Http\Controllers\Api\DeviceTokenController;
use App\Http\Controllers\Api\DoctorController;
use App\Http\Controllers\Api\DoctorImportExportController;
use App\Http\Controllers\Api\DoctorTaskProgressController;
use App\Http\Controllers\Api\EndodonticsXrayController;
use App\Http\Controllers\Api\GroupController;
use App\Http\Controllers\Api\LookupController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\OralMedicineChartController;
use App\Http\Controllers\Api\OrthodonticsRecordController;
use App\Http\Controllers\Api\PatientController;
use App\Http\Controllers\Api\PatientRegistrationController;
use App\Http\Controllers\Api\PatientRegistrationQrController;
use App\Http\Controllers\Api\PasswordResetController;
use App\Http\Controllers\Api\PaymentController;
use App\Http\Controllers\Api\AdvancedPeriodontalChartController;
use App\Http\Controllers\Api\PeriodontalChartController;
use App\Http\Controllers\Api\PreventionRecordController;
use App\Http\Controllers\Api\ProfileController;
use App\Http\Controllers\Api\ProsthodonticsRecordController;
use App\Http\Controllers\Api\RegisterDayController;
use App\Http\Controllers\Api\ServiceController;
use App\Http\Controllers\Api\SessionController;
use App\Http\Controllers\Api\SurgeryController;
use App\Http\Controllers\Api\SurgeryFollowUpController;
use App\Http\Controllers\Api\SurgeryImageController;
use App\Http\Controllers\Api\SurgeryMedicationController;
use App\Http\Controllers\Api\TaskController;
use App\Http\Controllers\Api\TaskInstanceController;
use App\Http\Controllers\Api\TaskProgressController;
use App\Http\Controllers\TaskInstanceAttachmentController;
use App\Http\Controllers\Api\TaskInstanceQrController;
use App\Http\Controllers\Api\CaseSheetController;
use App\Http\Controllers\Api\PendingTaskQrController;
use App\Http\Controllers\Api\TaskRegisterDaysController;
use App\Http\Controllers\Api\TreatmentMaterialController;
use App\Http\Controllers\Api\TreatmentPlanController;
use App\Http\Controllers\Api\TvBoardController;
use App\Http\Controllers\Api\WaitingScreenController;
use App\Http\Controllers\Api\WaitingScreenPairingController;
use App\Http\Controllers\Api\UserController;
use App\Http\Controllers\Api\UserPermissionController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| API Routes (Flutter mobile client)
|--------------------------------------------------------------------------
|
| Token-based (Sanctum) JSON API, versioned under /api/v1, separate from
| the Inertia web app's session-based routes in routes/web.php.
|
*/

// Named routes here are prefixed "api." — without this, Route::resource()
// in routes/web.php and Route::apiResource() here generate IDENTICAL route
// names by default (e.g. both produce "doctors.index"), and Laravel's named
// route lookup keeps only the last-registered match. That silently broke
// every redirect()->route(...) call in every web resource controller —
// e.g. DoctorController::store() would redirect to /api/v1/doctors (JSON)
// instead of /doctors (the Inertia page) after a successful create. Caught
// by testing an actual redirect Location header, not by reading the code —
// the pages still rendered fine standalone, so nothing looked broken until
// a create/update/delete flow was followed end-to-end.
Route::name('api.')->prefix('v1')->group(function () {
    // One endpoint for both account types now — see AuthController::login()'s
    // own docblock for how it tells a staff login from a doctor login apart.
    Route::post('/login', [AuthController::class, 'login']);

    // "نسيت كلمة المرور؟" — unified across both account types, same
    // reasoning as /login above. Throttled like the web equivalents
    // (routes/web.php's doctor.password.email / Breeze's password.email).
    // Sends a 5-minute one-time code instead of a link (2026-08-29, by
    // request; see App\Services\OtpPasswordResetBroker); /reset-password
    // below completes it natively in-app — a typed code has nowhere else
    // to go, unlike the old link, which could open the web reset page.
    Route::post('/forgot-password', [PasswordResetController::class, 'sendResetLink'])->middleware('throttle:6,1');
    Route::post('/reset-password', [PasswordResetController::class, 'reset'])->middleware('throttle:6,1');

    // Public, unauthenticated — mirrors the original app's tv_patients.php
    // waiting-room display. See TvBoardController docblock for a real
    // display bug in the original app this endpoint deliberately does not
    // reproduce.
    Route::get('/tv-board', TvBoardController::class);

    // Public, unauthenticated — feeds the /waiting-screen kiosk display.
    // See WaitingScreenController's own docblock.
    Route::get('/waiting-screen', WaitingScreenController::class);
    // Public — the QR image itself (the TV has no login). Confirming a
    // pairing (choosing a stage) is authenticated, further down in the
    // auth:sanctum group below.
    Route::get('/waiting-screen/pairings/{token}/qr', [WaitingScreenPairingController::class, 'qr']);

    // Public, unauthenticated — the Flutter login screen needs the clinic
    // logo/name before any Sanctum token exists. See BrandingController
    // docblock for why this hand-picks fields instead of reusing the
    // authenticated ClinicSettingController::show()'s full spread.
    Route::get('/branding', BrandingController::class);

    // Public, unauthenticated — the Windows desktop build polls this on
    // startup to self-update. See DesktopReleaseController docblock.
    Route::get('/desktop/version', DesktopReleaseController::class);

    // Public: activation codes and updates for the offline edition (2026-10-17).
    Route::post('/offline/activate', [\App\Http\Controllers\Api\OfflineLicenseController::class, 'activate'])->middleware('throttle:10,1');
    Route::get('/offline/latest', [\App\Http\Controllers\Api\OfflineLicenseController::class, 'latest'])->middleware('throttle:30,1');

    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/logout', [AuthController::class, 'logout']);
        Route::get('/me', [AuthController::class, 'me']);
        // Self-profile editing — GET /me above was read-only until now;
        // the web app already has this (ProfileController /
        // Doctor\ProfileController), just never exposed to the Sanctum
        // API. Both routes dual-dispatch on account type the same way
        // AuthController::me() does — see ProfileController docblock.
        Route::put('/me', [ProfileController::class, 'update']);
        Route::put('/me/password', [ProfileController::class, 'updatePassword']);

        // Phone as a QR scanner for the Windows app (2026-10-12); same
        // controller as the web app's, see ScannerPairingController.
        Route::post('/scanner-pairings', [\App\Http\Controllers\ScannerPairingController::class, 'store']);
        Route::get('/scanner-pairings/{scannerPairing}', [\App\Http\Controllers\ScannerPairingController::class, 'show']);
        Route::get('/scanner-pairings/{scannerPairing}/scans', [\App\Http\Controllers\ScannerPairingController::class, 'scans']);
        Route::delete('/scanner-pairings/{scannerPairing}', [\App\Http\Controllers\ScannerPairingController::class, 'destroy']);
        Route::put('/scanner-pairings/{scannerPairing}/photo-request', [\App\Http\Controllers\ScannerPairingController::class, 'photoRequest']);

        // The current principal's own notifications (Doctor or User) — see
        // NotificationController docblock. No permission/role middleware,
        // same as /me: everyone reads/manages only their own.
        Route::get('/notifications', [NotificationController::class, 'index']);
        Route::post('/notifications/read-all', [NotificationController::class, 'markAllRead']);
        Route::post('/notifications/{id}/read', [NotificationController::class, 'markRead']);

        // FCM device-token registration for push (see PushNotifier).
        Route::post('/device-tokens', [DeviceTokenController::class, 'store']);
        Route::delete('/device-tokens', [DeviceTokenController::class, 'destroy']);

        // Mirrors the web routes' permission: gating (routes/web.php) —
        // extended here too (2026-08-18), not just delete, so a Flutter
        // client can't bypass the granular grants that block a web session.
        // A Doctor-authenticated token is denied by EnsureUserHasPermission
        // outright (role/user_permissions are staff-only, see its docblock)
        // rather than crashing — these endpoints are staff-admin CRUD, not
        // something the Flutter doctor experience is expected to call.
        Route::apiResource('doctors', DoctorController::class)
            ->middlewareFor(['index', 'show'], 'permission:doctors,view')
            ->middlewareFor('store', 'permission:doctors,create')
            ->middlewareFor('update', 'permission:doctors,edit')
            ->middlewareFor('destroy', 'permission:doctors,delete');
        Route::get('/doctors/{doctor}/progress', [DoctorTaskProgressController::class, 'show'])
            ->middleware('permission:doctors,view');
        // Read-only NFC-tag lookup, shared by the doctors and groups admin
        // list screens (tap-to-search instead of typing a name) — see
        // DoctorController::nfcLookup()'s docblock for why this isn't
        // TaskProgressController::nfcScan() reused instead.
        Route::get('/doctors-nfc-lookup', [DoctorController::class, 'nfcLookup'])
            ->middleware('permission:doctors,view');
        Route::get('/doctors-template', [DoctorImportExportController::class, 'template']);
        Route::get('/doctors-export', [DoctorImportExportController::class, 'export'])->middleware('permission:doctors,export');
        Route::post('/doctors-import', [DoctorImportExportController::class, 'import'])->middleware('permission:doctors,create');

        Route::apiResource('patients', PatientController::class)
            ->middlewareFor(['index', 'show'], 'permission:patients,view')
            ->middlewareFor('store', 'permission:patients,create')
            ->middlewareFor('update', 'permission:patients,edit')
            ->middlewareFor('destroy', 'permission:patients,delete');

        // Reception-desk patient registration (services + days) — a
        // separate concept from `patients` above, see
        // App\Models\PatientRegistration's docblock. Gates reuse the
        // `patients`/`settings` modules exactly like the original app
        // does for these same screens (see PatientRegistrationController
        // and RegisterDayController docblocks) — no new permission module
        // invented.
        Route::get('/patient-registrations', [PatientRegistrationController::class, 'index'])
            ->middleware('permission:patients,view');
        Route::post('/patient-registrations', [PatientRegistrationController::class, 'store'])
            ->middleware('permission:patients,create');

        // Ticket QR: printed on the thermal ticket, scanned at the
        // payment desk. `scan`/`status` return the registration plus its
        // payment state — see PatientRegistrationQrController.
        Route::post('/patient-registrations/scan', [PatientRegistrationQrController::class, 'scan'])
            ->middleware('permission:patients,view');
        // Doctor-only twin for the case-sheet "مسح رمز المريض" autofill
        // button (2026-08-28) — deliberately outside `permission:`, which
        // rejects any Doctor principal outright; see
        // PatientRegistrationQrController::scanForCaseSheet()'s doc
        // comment.
        Route::post('/patient-registrations/scan-for-case-sheet', [PatientRegistrationQrController::class, 'scanForCaseSheet']);
        Route::get('/patient-registrations/{patientRegistration}/qr', [PatientRegistrationQrController::class, 'show'])
            ->middleware('permission:patients,view');
        Route::get('/patient-registrations/{patientRegistration}/status', [PatientRegistrationQrController::class, 'status'])
            ->middleware('permission:patients,view');

        // Infectious-disease screening gate (2026-08-26) — see
        // PatientScreeningGate/PatientRegistrationQrController::confirmScreening().
        Route::post('/patient-registrations/{patientRegistration}/screening', [PatientRegistrationQrController::class, 'confirmScreening'])
            ->middleware('permission:patient_screening,confirm');
        Route::post('/patient-registrations/{patientRegistration}/screening/reuse', [PatientRegistrationQrController::class, 'reuseScreening'])
            ->middleware('permission:patient_screening,confirm');

        Route::get('/register-days', [RegisterDayController::class, 'index']);
        Route::post('/register-days', [RegisterDayController::class, 'store'])->middleware('permission:settings,edit');
        Route::put('/register-days/{registerDay}', [RegisterDayController::class, 'update'])->middleware('permission:settings,edit');
        Route::delete('/register-days/{registerDay}', [RegisterDayController::class, 'destroy'])->middleware('permission:settings,edit');

        Route::get('/services', [ServiceController::class, 'index']);
        Route::post('/services', [ServiceController::class, 'store'])->middleware('permission:settings,edit');
        Route::put('/services/{service}', [ServiceController::class, 'update'])->middleware('permission:settings,edit');
        Route::delete('/services/{service}', [ServiceController::class, 'destroy'])->middleware('permission:settings,edit');

        // Day-governed diagnosis settings — see TaskRegisterDaysController's
        // docblock for why this is separate from Api\TaskController.
        Route::put('/tasks/{task}/register-days', [TaskRegisterDaysController::class, 'update'])
            ->middleware('permission:settings,edit');

        Route::get('/education-types', [LookupController::class, 'educationTypes']);
        Route::post('/education-types', [LookupController::class, 'storeEducationType'])->middleware('role:super_admin,admin');
        Route::put('/education-types/{educationType}', [LookupController::class, 'updateEducationType'])->middleware('role:super_admin,admin');
        Route::delete('/education-types/{educationType}', [LookupController::class, 'destroyEducationType'])->middleware('role:super_admin,admin');

        Route::get('/stages', [LookupController::class, 'stages']);
        Route::post('/stages', [LookupController::class, 'storeStage'])->middleware(['role:super_admin,admin', 'permission:stages,create']);
        Route::put('/stages/{stage}', [LookupController::class, 'updateStage'])->middleware(['role:super_admin,admin', 'permission:stages,edit']);
        Route::delete('/stages/{stage}', [LookupController::class, 'destroyStage'])->middleware(['role:super_admin,admin', 'permission:stages,delete']);

        // Confirming a scanned waiting-screen pairing QR with a chosen
        // stage — the Flutter side of the privacy gate described in
        // WaitingScreenPairingController's own docblock. No extra
        // role/permission gate: same reasoning as /stages just above (both
        // a staff User and a Doctor token may call this).
        Route::post('/waiting-screen/pairings/{token}/confirm', [WaitingScreenPairingController::class, 'confirm']);
        // The "enter the 4-digit code instead of scanning" alternative —
        // resolves to a token, then the app calls confirm() above as usual.
        Route::post('/waiting-screen/pairings/resolve-code', [WaitingScreenPairingController::class, 'resolveCode']);

        Route::get('/departments', [LookupController::class, 'departments']);
        Route::post('/departments', [LookupController::class, 'storeDepartment'])->middleware(['role:super_admin,admin', 'permission:departments,create']);
        Route::put('/departments/{department}', [LookupController::class, 'updateDepartment'])->middleware(['role:super_admin,admin', 'permission:departments,edit']);
        Route::delete('/departments/{department}', [LookupController::class, 'destroyDepartment'])->middleware(['role:super_admin,admin', 'permission:departments,delete']);

        // Before the apiResource registration — otherwise its {academic_session}
        // implicit-binding "show" route would try (and fail) to resolve "current" as an id.
        Route::get('/academic-sessions/current', [AcademicSessionController::class, 'current']);
        Route::apiResource('academic-sessions', AcademicSessionController::class);
        Route::put('/academic-sessions/{academic_session}/set-current', [AcademicSessionController::class, 'setCurrent']);

        // The list stays open (forms read it); changes need the module.
        // Never deleted (2026-10-15) — switch one off instead.
        Route::apiResource('case-sheet-types', CaseSheetTypeController::class)->except(['show', 'destroy'])
            ->middlewareFor('store', 'permission:case_sheet_types,create')
            ->middlewareFor('update', 'permission:case_sheet_types,edit');

        // Printable case sheets, as a document model the Flutter client can
        // lay out itself (see Api\CaseSheetPrintController). The Sanctum
        // guard carries either a Doctor or a User; which access rule applies
        // is decided in the controller, as on the web side.
        Route::get('/case-sheet-prints', [CaseSheetPrintController::class, 'index']);
        Route::get('/case-sheet-prints/{resource}/{record}', [CaseSheetPrintController::class, 'show'])
            ->whereIn('resource', array_keys(App\Support\CaseSheetPrint::SHEETS));

        // Form *layout* (no record) — see Api\CaseSheetFormController.
        Route::get('/case-sheet-forms', [CaseSheetFormController::class, 'index']);
        Route::get('/case-sheet-forms/{resource}', [CaseSheetFormController::class, 'show'])
            ->whereIn('resource', array_keys(App\Support\CaseSheetPrint::SHEETS));

        Route::get('/clinic-settings', [ClinicSettingController::class, 'show']);
        Route::put('/clinic-settings', [ClinicSettingController::class, 'update']);

        Route::get('/backup', [BackupController::class, 'status']);
        Route::post('/backup', [BackupController::class, 'store']);
        Route::put('/backup/auto', [BackupController::class, 'toggleAuto']);

        Route::apiResource('groups', GroupController::class);
        Route::get('/groups-available-doctors', [GroupController::class, 'availableDoctors']);
        Route::post('/groups/{group}/doctors', [GroupController::class, 'addDoctors']);
        Route::delete('/groups/{group}/doctors', [GroupController::class, 'removeDoctors']);

        Route::get('/tasks/scoring-templates', [TaskController::class, 'scoringTemplates'])
            ->middleware('permission:tasks,create');
        Route::apiResource('tasks', TaskController::class)
            ->middlewareFor(['index', 'show'], 'permission:tasks,view')
            ->middlewareFor('store', 'permission:tasks,create')
            ->middlewareFor('update', 'permission:tasks,edit')
            ->middlewareFor('destroy', 'permission:tasks,delete');
        Route::get('/my-task-instances', [TaskInstanceController::class, 'mine']);
        // The doctor's own department-grouped task summary — see
        // Api\TaskProgressController::mine()/DoctorTaskSummary.
        Route::get('/my-task-progress', [TaskProgressController::class, 'mine']);
        // "طلبات بدء المهام" (2026-10-14) — a doctor's own requests.
        Route::get('/my-task-start-requests', [\App\Http\Controllers\TaskStartRequestController::class, 'mine']);
        Route::post('/my-task-start-requests', [\App\Http\Controllers\TaskStartRequestController::class, 'store']);
        Route::delete('/my-task-start-requests/{taskStartRequest}', [\App\Http\Controllers\TaskStartRequestController::class, 'destroy']);
        // A doctor's photos of their own paper case sheets (2026-10-13).
        Route::get('/my-task-instances/{taskInstance}/attachments', [TaskInstanceAttachmentController::class, 'index'])
            ->name('my-attachments.index');
        Route::post('/my-task-instances/{taskInstance}/attachments', [TaskInstanceAttachmentController::class, 'store'])
            ->name('my-attachments.store');
        Route::delete('/my-task-instances/attachments/{attachment}', [TaskInstanceAttachmentController::class, 'destroy'])
            ->name('my-attachments.destroy');
        Route::get('/task-instances/{taskInstance}', [TaskInstanceController::class, 'show']);
        Route::post('/task-instances', [TaskInstanceController::class, 'store']);
        Route::put('/task-instances/{taskInstance}', [TaskInstanceController::class, 'update']);
        Route::delete('/task-instances/{taskInstance}', [TaskInstanceController::class, 'destroy']);
        Route::post('/task-instances/{taskInstance}/confirm-paper', [TaskInstanceController::class, 'confirmPaper']);
        Route::get('/task-instances/{taskInstance}/qr', [TaskInstanceQrController::class, 'show']);
        Route::post('/task-instances/scan', [TaskInstanceQrController::class, 'scan']);
        // Resolves a case's clinical-form resource (Flutter's equivalent of
        // the web's CaseSheetController::open() redirect) — same
        // CaseSheetResolver, same access rules, JSON instead of a redirect.
        Route::get('/task-instances/{taskInstance}/case-sheet', [CaseSheetController::class, 'open']);
        // The task's points on its case sheet (2026-10-17), the app's twin of
        // the web's case-sheets.instance-work routes: the same controller and
        // rules (a doctor reads only their own case; saving needs
        // task_progress finish), so both clients read and write one record.
        Route::get('/case-sheets/instances/{taskInstance}/work', [\App\Http\Controllers\TaskWorkController::class, 'show'])
            ->name('case-sheets.instance-work');
        Route::put('/case-sheets/instances/{taskInstance}/work', [\App\Http\Controllers\TaskWorkController::class, 'update'])
            ->name('case-sheets.instance-work.update');
        // Optional pre-instance draft (2026-08-28) — see CaseSheetController::openForTask()'s doc comment.
        Route::get('/tasks/{task}/case-sheet-draft', [CaseSheetController::class, 'openForTask']);
        // The doctor's own "pending task" QR (task+doctor, no instance yet
        // — see Doctor\PendingTasksQrController's docblock for why "pending"
        // means something different here than task_instances.status). New
        // 2026-08-27: Flutter had no way to generate this PNG at all before.
        // `index` (2026-09-01) is the dedicated "رموز المهام المعلقة" list
        // itself, not just the per-task PNG — see the controller's own
        // docblock.
        Route::get('/pending-tasks', [PendingTaskQrController::class, 'index']);
        Route::get('/pending-tasks/{task}/qr', [PendingTaskQrController::class, 'show']);

        // "Active sessions" (2026-09-01) — see Api\SessionController's own
        // docblock for why this lists Sanctum tokens only, not the web
        // app's separate session-cookie auth.
        Route::get('/sessions', [SessionController::class, 'index']);
        Route::delete('/sessions/{id}', [SessionController::class, 'destroy']);
        Route::post('/sessions/logout-all', [SessionController::class, 'logoutAll']);

        // NFC doctor lookup — Flutter-only (browsers can't read NFC), the
        // web's session-based /task-progress/scan stays QR-only and is
        // untouched. See Api\TaskProgressController's docblock.
        Route::post('/task-progress/nfc-scan', [TaskProgressController::class, 'nfcScan'])
            ->middleware('permission:task_progress,view');
        Route::post('/task-progress/start', [TaskProgressController::class, 'start'])
            ->middleware('permission:task_progress,start');
        // Doctors' requests to start a task (2026-10-14).
        Route::get('/task-progress/requests', [\App\Http\Controllers\TaskStartRequestController::class, 'index'])
            ->middleware('permission:task_progress,view');
        Route::post('/task-progress/requests/{taskStartRequest}/approve', [\App\Http\Controllers\TaskStartRequestController::class, 'approve'])
            ->middleware('permission:task_progress,start');
        Route::post('/task-progress/requests/{taskStartRequest}/reject', [\App\Http\Controllers\TaskStartRequestController::class, 'reject'])
            ->middleware('permission:task_progress,start');
        // The full matrix screen — see Api\TaskProgressController's
        // docblock. Same permission gates as their web counterparts.
        Route::get('/task-progress/filters', [TaskProgressController::class, 'filters'])
            ->middleware('permission:task_progress,view');
        Route::get('/task-progress/groups/{group}', [TaskProgressController::class, 'group'])
            ->middleware('permission:task_progress,view');
        Route::get('/task-progress/stages/{stage}', [TaskProgressController::class, 'stage'])
            ->middleware('permission:task_progress,view');
        // Paper case-sheet photos (2026-10-13) — see TaskInstanceAttachmentController.
        Route::get('/task-progress/instances/{taskInstance}/attachments', [TaskInstanceAttachmentController::class, 'index'])
            ->middleware('permission:task_progress,view')->name('task-attachments.index');
        Route::post('/task-progress/instances/{taskInstance}/attachments', [TaskInstanceAttachmentController::class, 'store'])
            ->middleware('permission:task_progress,view')->name('task-attachments.store');
        Route::put('/task-progress/attachments/{attachment}/note', [TaskInstanceAttachmentController::class, 'note'])
            ->middleware('permission:task_progress,view')->name('task-attachments.note');
        Route::delete('/task-progress/attachments/{attachment}', [TaskInstanceAttachmentController::class, 'destroy'])
            ->middleware('permission:task_progress,view')->name('task-attachments.destroy');
        Route::put('/task-progress/instances/{taskInstance}/complete', [TaskProgressController::class, 'complete'])
            ->middleware('permission:task_progress,finish');
        Route::put('/task-progress/instances/{taskInstance}', [TaskProgressController::class, 'updateInstance'])
            ->middleware('permission:task_progress,finish');

        // Was missing entirely on the API side until 2026-08-28 — a real,
        // pre-existing gap found while building the supervisor-preview
        // feature: `EnforceCaseSheetAccess` (staff-view-only + doctor-owns-
        // own-record) was wired into routes/web.php only, so any
        // authenticated Sanctum principal could read/write/delete any of
        // these resources via the mobile API regardless of ownership.
        // `App\Services\CaseSheetAccess::doctor()` was extended the same
        // day to recognize a Sanctum-authenticated Doctor (previously only
        // checked the web session's `doctor` guard), so this middleware
        // behaves identically here to its web counterpart.
        Route::middleware('case-sheet')->group(function () {
            Route::apiResource('dental-charts', DentalChartController::class)->except('destroy');
        });

        // A canal's working-length X-ray on the Operative sheet's
        // Endodontics section (2026-09-03) — deliberately outside the
        // `case-sheet` group above: there's no case-sheet record to check
        // ownership of yet on a create flow, and no `dental-charts`-shaped
        // route parameter for `EnforceCaseSheetAccess` to bind against.
        // See `EndodonticsXrayController`'s own doc comment.
        Route::post('/endodontics-xrays', [EndodonticsXrayController::class, 'store']);

        Route::apiResource('appointments', AppointmentController::class);
        // Income overview (2026-10-17) — declared before the resource so
        // "stats" isn't bound as a {payment}. No `update`: payments are
        // not edited by hand any more (see PaymentController).
        Route::get('/payments/stats', [PaymentController::class, 'stats'])->name('payments.stats');
        Route::apiResource('payments', PaymentController::class)->except(['update']);

        Route::get('/activity-logs', [ActivityLogController::class, 'index']);

        Route::get('/permissions', [UserPermissionController::class, 'index'])->name('permissions.index');
        Route::get('/permissions/{user}', [UserPermissionController::class, 'show'])->name('permissions.show');
        Route::put('/permissions/{user}', [UserPermissionController::class, 'update'])->name('permissions.update');

        // New staff/admin account creation — the 'users' module has sat in
        // PermissionMatrix since it was built, unused by any route (the
        // same class of gap as 'departments', see its own comment above).
        // This is the first route that actually checks it.
        Route::get('/users/form-options', [UserController::class, 'formOptions'])->middleware('permission:users,create');
        Route::post('/users', [UserController::class, 'store'])->middleware('permission:users,create');

        // Clinical specialty records — each mirrors the pattern above
        // (index scoped to the authenticated doctor where the table has a
        // doctor_id column; full CRUD; validation generated from the real
        // imported schema). See README.md for which tables were skipped
        // and why.
        Route::middleware('case-sheet')->group(function () {
            foreach ([
                'advanced-periodontal-charts' => AdvancedPeriodontalChartController::class,
                'complete-denture-records' => CompleteDentureRecordController::class,
                'oral-medicine-charts' => OralMedicineChartController::class,
                'orthodontics-records' => OrthodonticsRecordController::class,
                'periodontal-charts' => PeriodontalChartController::class,
                'prevention-records' => PreventionRecordController::class,
                'prosthodontics-records' => ProsthodonticsRecordController::class,
                'surgeries' => SurgeryController::class,
                'surgery-follow-ups' => SurgeryFollowUpController::class,
                'surgery-images' => SurgeryImageController::class,
                'surgery-medications' => SurgeryMedicationController::class,
                'treatment-plans' => TreatmentPlanController::class,
                'treatment-materials' => TreatmentMaterialController::class,
            ] as $uri => $controller) {
                // The case sheets themselves are never deleted (2026-10-15).
                Route::apiResource($uri, $controller)->parameters([$uri => 'record'])
                    ->except(in_array($uri, \App\Support\CaseSheetsKept::RESOURCES, true) ? ['destroy'] : []);
            }

            // One stage date/grade saved as soon as it changes (2026-10-15).
            foreach (['prosthodontics-records' => ProsthodonticsRecordController::class, 'complete-denture-records' => CompleteDentureRecordController::class] as $uri => $controller) {
                Route::patch("$uri/{record}/stage-field", [$controller, 'stageField'])->name("$uri.stage-field");
            }
        });
    });
});
