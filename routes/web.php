<?php

use App\Http\Controllers\AcademicSessionController;
use App\Http\Controllers\ActivityLogController;
use App\Http\Controllers\AppointmentController;
use App\Http\Controllers\BackupController;
use App\Http\Controllers\CaseSheetController;
use App\Http\Controllers\CaseSheetPrintController;
use App\Http\Controllers\CaseSheetTypeController;
use App\Http\Controllers\ClinicSettingController;
use App\Http\Controllers\CompleteDentureRecordController;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\DentalChartController;
use App\Http\Controllers\DepartmentController;
use App\Http\Controllers\DepartmentRoleAssignmentController;
use App\Http\Controllers\DoctorController;
use App\Http\Controllers\DoctorPrintController;
use App\Http\Controllers\DoctorTaskProgressController;
use App\Http\Controllers\DoctorImportExportController;
use App\Http\Controllers\Auth\DoctorAuthenticatedSessionController;
use App\Http\Controllers\Auth\DoctorPasswordResetController;
use App\Http\Controllers\Auth\GoogleAuthController;
use App\Http\Controllers\Doctor\DashboardController as DoctorDashboardController;
use App\Http\Controllers\Doctor\ProfileController as DoctorProfileController;
use App\Http\Controllers\Doctor\TaskInstanceController as DoctorTaskInstanceController;
use App\Http\Controllers\Doctor\RequiredTasksController as DoctorRequiredTasksController;
use App\Http\Controllers\Doctor\ProgressController as DoctorProgressController;
use App\Http\Controllers\Doctor\PendingTasksQrController as DoctorPendingTasksQrController;
use App\Http\Controllers\EducationTypeController;
use App\Http\Controllers\GroupController;
use App\Http\Controllers\OralMedicineChartController;
use App\Http\Controllers\OrthodonticsRecordController;
use App\Http\Controllers\PatientController;
use App\Http\Controllers\PatientRegistrationController;
use App\Http\Controllers\PatientRegistrationPrintController;
use App\Http\Controllers\PaymentController;
use App\Http\Controllers\PeriodontalChartController;
use App\Http\Controllers\PreventionRecordController;
use App\Http\Controllers\ProfileController;
use App\Http\Controllers\ProsthodonticsRecordController;
use App\Http\Controllers\RegisterSettingsController;
use App\Http\Controllers\StageController;
use App\Http\Controllers\SurgeryController;
use App\Http\Controllers\SurgeryFollowUpController;
use App\Http\Controllers\SurgeryImageController;
use App\Http\Controllers\SurgeryMedicationController;
use App\Http\Controllers\TaskController;
use App\Http\Controllers\TaskInstanceController;
use App\Http\Controllers\TaskProgressController;
use App\Http\Controllers\TreatmentMaterialController;
use App\Http\Controllers\TreatmentPlanController;
use App\Http\Controllers\UserController;
use App\Http\Controllers\UserPermissionController;
use App\Models\ClinicSetting;
use App\Models\Department;
use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Patient;
use App\Models\Stage;
use Illuminate\Support\Facades\Route;
use Inertia\Inertia;

// The public landing page — teaching-hospital branding pulled from the
// same ClinicSetting row every print view and the admin settings screen
// already use, plus real counts (not placeholder marketing numbers) so
// the page reflects this actual install rather than generic copy.
Route::get('/', function () {
    $settings = ClinicSetting::current();

    return Inertia::render('Welcome', [
        'canLogin' => Route::has('login'),
        'clinic' => [
            'name' => $settings->clinic_name,
            'description' => $settings->clinic_description,
            'address' => $settings->clinic_address,
            'phone' => $settings->clinic_phone,
            'email' => $settings->clinic_email,
            'website' => $settings->clinic_website,
            'workingHours' => $settings->clinic_working_hours,
            'universityName' => $settings->university_name,
            'collegeName' => $settings->college_name,
            'logoUrl' => $settings->logoUrl(),
            'universityLogoUrl' => $settings->universityLogoUrl(),
        ],
        'stats' => [
            'doctors' => Doctor::count(),
            'departments' => Department::count(),
            'stages' => Stage::count(),
            'educationTypes' => EducationType::count(),
        ],
    ]);
});

// Public waiting-room display — no auth, matches the original app's
// tv_patients.php being a public screen, not part of the admin app.
Route::get('/tv', function () {
    return Inertia::render('TvBoard', [
        'educationTypes' => EducationType::orderBy('name')->get(['id', 'name']),
        'stages' => Stage::orderBy('name')->get(['id', 'name', 'education_type_id']),
    ]);
})->name('tv-board');

// Doctor-facing area — separate guard/session from the staff `web` guard
// above (see config/auth.php `doctor` guard, `doctors` table). Login itself
// is unified now (see `routes/auth.php`'s single `/login` — `LoginRequest`
// tries the `web` guard then the `doctor` guard against the same "email or
// username" field), so there's no separate `/doctor/login` route anymore.

// Forgot/reset password for the doctor guard — Breeze only ships this for
// staff users, and the original app has no password reset at all. Kept
// as its own flow (not merged into the unified login) since the token
// broker needs to know which table to reset against.
Route::get('/doctor/forgot-password', [DoctorPasswordResetController::class, 'request'])->name('doctor.password.request');
Route::post('/doctor/forgot-password', [DoctorPasswordResetController::class, 'email'])
    ->middleware('throttle:6,1')->name('doctor.password.email');
Route::get('/doctor/reset-password/{token}', [DoctorPasswordResetController::class, 'reset'])->name('doctor.password.reset');
Route::post('/doctor/reset-password', [DoctorPasswordResetController::class, 'update'])->name('doctor.password.store');

// "Sign in with Google" — shared by the one login page, auto-detecting
// staff vs. doctor from the Google account's email the same way the
// unified login form does (see GoogleAuthController::callback()).
Route::get('/auth/google/redirect', [GoogleAuthController::class, 'redirect'])->name('auth.google.redirect');
Route::get('/auth/google/callback', [GoogleAuthController::class, 'callback'])->name('auth.google.callback');

Route::middleware('auth:doctor')->group(function () {
    Route::post('/doctor/logout', [DoctorAuthenticatedSessionController::class, 'destroy'])->name('doctor.logout');
    Route::get('/doctor/dashboard', [DoctorDashboardController::class, 'index'])->name('doctor.dashboard');
    // Two forms, as in the original's profile pages: profile details
    // (POST — carries a file upload) and a separate password change.
    Route::get('/doctor/profile', [DoctorProfileController::class, 'edit'])->name('doctor.profile.edit');
    Route::post('/doctor/profile', [DoctorProfileController::class, 'update'])->name('doctor.profile.update');
    Route::put('/doctor/profile/password', [DoctorProfileController::class, 'updatePassword'])->name('doctor.profile.password');
    Route::put('/doctor/task-instances/{taskInstance}', [DoctorTaskInstanceController::class, 'update'])->name('doctor.task-instances.update');

    // The remaining three items of the original's doctor navbar
    // (doctor_navbar.php), plus its academic-session switcher.
    Route::get('/doctor/required-tasks', [DoctorRequiredTasksController::class, 'index'])->name('doctor.required-tasks');
    Route::get('/doctor/progress', [DoctorProgressController::class, 'index'])->name('doctor.progress');
    Route::get('/doctor/pending-qr', [DoctorPendingTasksQrController::class, 'index'])->name('doctor.pending-qr');
    Route::get('/doctor/pending-qr/{task}', [DoctorPendingTasksQrController::class, 'qr'])->name('doctor.pending-qr.image');
    // فتح النموذج — routes a task instance to its case sheet by type code.
    Route::get('/doctor/case-sheet/{taskInstance}', [CaseSheetController::class, 'open'])->name('doctor.case-sheet');
    // Optional pre-instance draft (2026-08-28) — see CaseSheetController::openForTask()'s
    // doc comment: no TaskInstance/screening gate involved.
    Route::get('/doctor/case-sheet/for-task/{task}', [CaseSheetController::class, 'openForTask'])->name('doctor.case-sheet.for-task');
    Route::post('/doctor/session', [AcademicSessionController::class, 'select'])->name('doctor.session.select');
});

// Printable case sheets — port of the doctor/*_print_html.php family.
// Deliberately open to **both** guards, exactly as the original's print
// pages are (`if (!isset($_SESSION['doctor_id']) && !isset($_SESSION['user_id']))`):
// a doctor prints their own sheet, staff print any sheet they may open.
// Which of the two applies is decided inside the controller, not here.
Route::middleware('auth:web,doctor')->group(function () {
    Route::get('/case-sheets/{resource}/{record}/print', [CaseSheetPrintController::class, 'show'])
        ->whereIn('resource', array_keys(App\Support\CaseSheetPrint::SHEETS))
        ->name('case-sheets.print');

    // The on-screen "رمز QR" button every case sheet in the original shows
    // once it's tied to a task instance — port of surgery.php's "رمز QR"
    // button, which calls a showTaskQrCode() only ever *defined* in
    // required_tasks.php's own <script> block; surgery.php never includes
    // that file, only doctor_navbar.php, so clicking it there throws
    // "showTaskQrCode is not defined" in the original itself. Rebuilt here
    // as an actually-working button reusing TaskInstanceController::qr()
    // (same {"type":"task_instance","id":…} payload TaskProgressController::scan()
    // and CaseSheetController::open() already resolve) rather than
    // faithfully reproducing the original's dead onclick handler.
    // `case-sheet` middleware's ownership check applies here too — a
    // doctor can only fetch the QR for their own task instance.
    Route::get('/case-sheets/instances/{taskInstance}/qr', [TaskInstanceController::class, 'qr'])
        ->middleware('case-sheet')
        ->name('case-sheets.instance-qr');
});

Route::middleware(['auth', 'verified'])->group(function () {
    Route::get('/dashboard', [DashboardController::class, 'index'])->name('dashboard');
    // On-demand section of the original dashboard
    // (ajax/dashboard_tasks_by_dept.php).
    Route::get('/dashboard/tasks-by-education-type/{educationType}', [DashboardController::class, 'tasksByEducationType'])
        ->name('dashboard.tasks-by-education-type');
});

Route::middleware('auth')->group(function () {
    Route::get('/profile', [ProfileController::class, 'edit'])->name('profile.edit');
    Route::post('/profile', [ProfileController::class, 'update'])->name('profile.update');
    Route::put('/profile/password', [ProfileController::class, 'updatePassword'])->name('profile.password');

    Route::middleware('role:super_admin,admin,editor')->group(function () {
        // Doctor deletion also requires the granular 'doctors.delete' grant
        // (App\Services\PermissionManager) on top of the role check above.
        // Extended (2026-08-18) from delete-only to every action — see
        // README "Granular permissions" for why delete came first and why
        // the rest followed the same one-line-per-route pattern.
        Route::resource('doctors', DoctorController::class)->except(['show', 'destroy'])
            ->middlewareFor('index', 'permission:doctors,view')
            ->middlewareFor(['create', 'store'], 'permission:doctors,create')
            ->middlewareFor(['edit', 'update'], 'permission:doctors,edit');
        Route::delete('/doctors/{doctor}', [DoctorController::class, 'destroy'])
            ->middleware('permission:doctors,delete')
            ->name('doctors.destroy');
        Route::delete('/doctors-bulk', [DoctorController::class, 'destroyMany'])
            ->middleware('permission:doctors,delete')
            ->name('doctors.destroy-many');

        Route::resource('patients', PatientController::class)->except(['show', 'destroy'])
            ->middlewareFor('index', 'permission:patients,view')
            ->middlewareFor(['create', 'store'], 'permission:patients,create')
            ->middlewareFor(['edit', 'update'], 'permission:patients,edit');
        Route::delete('/patients/{patient}', [PatientController::class, 'destroy'])
            ->middleware('permission:patients,delete')
            ->name('patients.destroy');

        // Reception-desk patient registration (services + days) — separate
        // from `patients` above, see App\Models\PatientRegistration's
        // docblock. Gates reuse the `patients` module exactly like
        // admin/patient_register.php does in the original (no new
        // permission module invented).
        Route::get('/patient-registrations', [PatientRegistrationController::class, 'index'])
            ->middleware('permission:patients,view')->name('patient-registrations.index');
        Route::get('/patient-registrations/create', [PatientRegistrationController::class, 'create'])
            ->middleware('permission:patients,create')->name('patient-registrations.create');
        // Autocomplete for Payments/Create.vue's "ابحث عن مريض" field
        // (2026-08-26).
        Route::get('/patient-registrations/search', [PatientRegistrationController::class, 'search'])
            ->middleware('permission:patients,view')->name('patient-registrations.search');
        Route::post('/patient-registrations', [PatientRegistrationController::class, 'store'])
            ->middleware('permission:patients,create')->name('patient-registrations.store');
        Route::get('/patient-registrations/{patientRegistration}/qr', [PatientRegistrationController::class, 'qr'])
            ->middleware('permission:patients,view')->name('patient-registrations.qr');
        // Reprint an already-registered patient's ticket — same gate as
        // `.qr` (a read/display action, not a create).
        Route::get('/patient-registrations/{patientRegistration}/print', [PatientRegistrationPrintController::class, 'ticket'])
            ->middleware('permission:patients,view')->name('patient-registrations.print');
        // Payment-desk scanner — see Api\PatientRegistrationQrController's
        // docblock for the payload convention and Step 5 of Phase 5's plan.
        Route::post('/patient-registrations/scan', [PatientRegistrationController::class, 'scan'])
            ->middleware('permission:patients,view')->name('patient-registrations.scan');

        // Infectious-disease screening gate (2026-08-26) — see
        // PatientScreeningGate/PatientRegistrationController::confirmScreening().
        Route::post('/patient-registrations/{patientRegistration}/screening', [PatientRegistrationController::class, 'confirmScreening'])
            ->middleware('permission:patient_screening,confirm')->name('patient-registrations.screening');

        Route::get('/doctors-import', [DoctorImportExportController::class, 'showImport'])
            ->middleware('permission:doctors,create')
            ->name('doctors.import.show');
        Route::post('/doctors-import', [DoctorImportExportController::class, 'import'])
            ->middleware('permission:doctors,create')
            ->name('doctors.import');
        Route::get('/doctors-template', [DoctorImportExportController::class, 'template'])->name('doctors.template');
        Route::get('/doctors-export', [DoctorImportExportController::class, 'export'])
            ->middleware('permission:doctors,export')
            ->name('doctors.export');

        // Printable views — port of admin/print_doctors.php and
        // print_doctor_card.php. Gated on doctors.export, the closest
        // action the original's matrix defines for "take the data out".
        Route::get('/doctors-print', [DoctorPrintController::class, 'roster'])
            ->middleware('permission:doctors,export')
            ->name('doctors.print');
        Route::get('/doctors/{doctor}/card', [DoctorPrintController::class, 'card'])
            ->middleware('permission:doctors,export')
            ->name('doctors.card');
    });

    Route::middleware('role:super_admin,admin')->group(function () {
        Route::resource('education-types', EducationTypeController::class)->except(['show', 'create', 'edit'])
            ->middlewareFor('index', 'permission:education_types,view')
            ->middlewareFor('store', 'permission:education_types,create')
            ->middlewareFor('update', 'permission:education_types,edit')
            ->middlewareFor('destroy', 'permission:education_types,delete');
        Route::resource('stages', StageController::class)->except(['show', 'create', 'edit'])
            ->middlewareFor('index', 'permission:stages,view')
            ->middlewareFor('store', 'permission:stages,create')
            ->middlewareFor('update', 'permission:stages,edit')
            ->middlewareFor('destroy', 'permission:stages,delete');

        // 'departments' has been in UserPermissionController::MODULES since
        // the permission matrix was built, but no route ever actually
        // checked it — the matrix UI could grant/revoke a permission with
        // no enforcement anywhere. Fixed by wiring the same pattern used
        // for doctors/patients above.
        Route::resource('departments', DepartmentController::class)->except(['show', 'create', 'edit'])
            ->middlewareFor('index', 'permission:departments,view')
            ->middlewareFor('store', 'permission:departments,create')
            ->middlewareFor('update', 'permission:departments,edit')
            ->middlewareFor('destroy', 'permission:departments,delete');

        Route::resource('academic-sessions', AcademicSessionController::class)->except(['create', 'edit']);
        Route::put('/academic-sessions/{academic_session}/set-current', [AcademicSessionController::class, 'setCurrent'])->name('academic-sessions.set-current');
        Route::post('/academic-sessions/select', [AcademicSessionController::class, 'select'])->name('academic-sessions.select');

        Route::resource('case-sheet-types', CaseSheetTypeController::class)->except(['show', 'create', 'edit']);

        Route::resource('groups', GroupController::class)->except(['show', 'create', 'edit'])
            ->middlewareFor('index', 'permission:groups,view')
            ->middlewareFor('store', 'permission:groups,create')
            ->middlewareFor('update', 'permission:groups,edit')
            ->middlewareFor('destroy', 'permission:groups,delete');
        Route::get('/groups-available-doctors', [GroupController::class, 'availableDoctors'])
            ->middleware('permission:groups,view')->name('groups.available-doctors');
        // Changing a group's membership is an edit of the group.
        Route::post('/groups/{group}/doctors', [GroupController::class, 'addDoctors'])
            ->middleware('permission:groups,edit')->name('groups.doctors.add');
        Route::delete('/groups/{group}/doctors', [GroupController::class, 'removeDoctors'])
            ->middleware('permission:groups,edit')->name('groups.doctors.remove');

        // Matches admin/doctor_task_progress.php's own access check
        // (in_array($_SESSION['role'], ['admin', 'super_admin'])) — this one
        // route is admin-only, not editor, unlike doctors.* above.
        Route::get('/doctors/{doctor}/progress', [DoctorTaskProgressController::class, 'show'])->name('doctors.progress');

        // The admin-side task progress browser (day → stage → group →
        // department-tabbed doctor matrix) — distinct from the per-doctor
        // screen above. See TaskProgressController's docblock.
        // The original gates these with its own task_progress permissions
        // (get_group_doctors.php checks `start`/`finish`/`open_case_sheet`
        // per button; assign_task_ajax.php and mark_task_completed.php
        // re-check `start`/`finish` server-side). Now that the matrix
        // carries those actions, the routes enforce them.
        Route::get('/task-progress', [TaskProgressController::class, 'index'])
            ->middleware('permission:task_progress,view')->name('task-progress.index');
        Route::get('/task-progress/groups/{group}', [TaskProgressController::class, 'group'])
            ->middleware('permission:task_progress,view')->name('task-progress.group');
        // Staff-side "فتح النموذج" — the original gates this with
        // task_progress.open_case_sheet, checked inside the controller too.
        Route::get('/case-sheet/{taskInstance}', [CaseSheetController::class, 'open'])
            ->middleware('permission:task_progress,open_case_sheet')->name('case-sheet.open');
        // Resolves a scanned QR code — the page's scanner modal, ported
        // from the original's task_progress_view.php.
        Route::post('/task-progress/scan', [TaskProgressController::class, 'scan'])
            ->middleware('permission:task_progress,view')->name('task-progress.scan');
        Route::post('/task-progress/start', [TaskProgressController::class, 'start'])
            ->middleware('permission:task_progress,start')->name('task-progress.start');
        Route::put('/task-progress/instances/{taskInstance}/complete', [TaskProgressController::class, 'complete'])
            ->middleware('permission:task_progress,finish')->name('task-progress.complete');
        // The original guards this with `finish || edit` — but
        // `task_progress.edit` is **never defined in its own permission
        // matrix**, so it can never be granted and the check collapses to
        // `finish`. (Its update_task_status.php checks `edit` *alone*,
        // which therefore denies every non-super_admin — a latent bug not
        // reproduced here.) Gated on `finish`, matching effective behaviour.
        Route::put('/task-progress/instances/{taskInstance}', [TaskProgressController::class, 'updateInstance'])
            ->middleware('permission:task_progress,finish')->name('task-progress.update-instance');

        Route::get('/activity-logs', [ActivityLogController::class, 'index'])->name('activity-logs.index');

        Route::get('/permissions', [UserPermissionController::class, 'index'])->name('permissions.index');
        Route::get('/permissions/{user}', [UserPermissionController::class, 'edit'])->name('permissions.edit');
        Route::put('/permissions/{user}', [UserPermissionController::class, 'update'])->name('permissions.update');

        // New staff/admin account creation — see Api\UserController's
        // docblock for why 'users' was an unused permission-matrix module
        // until now.
        Route::get('/users/create', [UserController::class, 'create'])
            ->middleware('permission:users,create')->name('users.create');
        Route::post('/users', [UserController::class, 'store'])
            ->middleware('permission:users,create')->name('users.store');

        // admin/clinic_settings.php opens with
        // `$perm->requirePermission('settings', 'edit')` — now that
        // `settings` is in the matrix (it was missing from the earlier
        // port's module list), that gate is real here too.
        Route::get('/clinic-settings', [ClinicSettingController::class, 'edit'])
            ->middleware('permission:settings,view')->name('clinic-settings.edit');
        Route::put('/clinic-settings', [ClinicSettingController::class, 'update'])
            ->middleware('permission:settings,edit')->name('clinic-settings.update');
        Route::post('/clinic-settings/test-email', [ClinicSettingController::class, 'sendTestEmail'])
            ->middleware(['permission:settings,edit', 'throttle:6,1'])->name('clinic-settings.test-email');

        // Services/days config for patient registration — mirrors
        // admin/register_settings.php, gated the same way it is there
        // ($perm->requirePermission('settings', 'edit')).
        Route::get('/patient-registrations/settings', [RegisterSettingsController::class, 'edit'])
            ->middleware('permission:settings,edit')->name('patient-registrations.settings');
        Route::post('/register-days', [RegisterSettingsController::class, 'storeDay'])
            ->middleware('permission:settings,edit')->name('register-days.store');
        Route::delete('/register-days/{registerDay}', [RegisterSettingsController::class, 'destroyDay'])
            ->middleware('permission:settings,edit')->name('register-days.destroy');
        Route::post('/register-services', [RegisterSettingsController::class, 'storeService'])
            ->middleware('permission:settings,edit')->name('register-services.store');
        Route::put('/register-services/{service}', [RegisterSettingsController::class, 'updateService'])
            ->middleware('permission:settings,edit')->name('register-services.update');
        Route::delete('/register-services/{service}', [RegisterSettingsController::class, 'destroyService'])
            ->middleware('permission:settings,edit')->name('register-services.destroy');
        Route::put('/tasks/{task}/register-days', [RegisterSettingsController::class, 'updateTaskDays'])
            ->middleware('permission:settings,edit')->name('tasks.register-days.update');

        Route::get('/department-roles', [DepartmentRoleAssignmentController::class, 'index'])->name('department-roles.index');
        Route::post('/department-roles', [DepartmentRoleAssignmentController::class, 'store'])->name('department-roles.store');
        Route::put('/department-roles/{departmentRoleAssignment}/toggle', [DepartmentRoleAssignmentController::class, 'toggle'])->name('department-roles.toggle');
        Route::delete('/department-roles/{departmentRoleAssignment}', [DepartmentRoleAssignmentController::class, 'destroy'])->name('department-roles.destroy');

        // admin/backup.php — plain role check in the original, no
        // granular permission, hence this group rather than a
        // `permission:` middleware. MikroTik upload intentionally excluded.
        Route::get('/backup', [BackupController::class, 'index'])->name('backup.index');
        Route::post('/backup', [BackupController::class, 'store'])->name('backup.store');
        Route::put('/backup/auto', [BackupController::class, 'toggleAuto'])->name('backup.toggle-auto');
        Route::get('/backup/{filename}/download', [BackupController::class, 'download'])->name('backup.download');
    });

    Route::middleware('role:super_admin,admin,editor')->group(function () {
        // Extended (2026-08-18) from delete-only to every action, same
        // pattern as doctors/patients/departments above.
        Route::resource('tasks', TaskController::class)->except('destroy')
            ->middlewareFor(['index', 'show'], 'permission:tasks,view')
            ->middlewareFor(['create', 'store'], 'permission:tasks,create')
            ->middlewareFor(['edit', 'update'], 'permission:tasks,edit');
        Route::delete('/tasks/{task}', [TaskController::class, 'destroy'])
            ->middleware('permission:tasks,delete')
            ->name('tasks.destroy');
        Route::post('/tasks/{task}/instances', [TaskInstanceController::class, 'store'])->name('task-instances.store');
        Route::put('/task-instances/{taskInstance}', [TaskInstanceController::class, 'update'])->name('task-instances.update');
        Route::delete('/task-instances/{taskInstance}', [TaskInstanceController::class, 'destroy'])->name('task-instances.destroy');
        Route::get('/task-instances/{taskInstance}/qr', [TaskInstanceController::class, 'qr'])->name('task-instances.qr');

        // dental-charts (the operative sheet) moved to the both-guards
        // case-sheet group at the bottom of this file.

        // AppointmentController has no show() method — 'show' was
        // previously registered anyway (Route::resource doesn't validate
        // this at registration time) and would have thrown a
        // BadMethodCallException if anyone ever hit GET /appointments/{id}
        // directly. Never triggered (nothing links to appointments.show,
        // no Show.vue exists), but a real latent crash — excluded here.
        Route::resource('appointments', AppointmentController::class)->except(['show', 'destroy']);
        Route::delete('/appointments/{appointment}', [AppointmentController::class, 'destroy'])
            ->name('appointments.destroy');
        Route::put('/appointments/{appointment}/toggle-pinned', [AppointmentController::class, 'togglePinned'])->name('appointments.toggle-pinned');

        Route::resource('payments', PaymentController::class)->only(['index', 'create', 'store']);
        Route::delete('/payments/{payment}', [PaymentController::class, 'destroy'])
            ->name('payments.destroy');

        // Clinical specialty records — hub page + generic Specialty/Index
        // and Specialty/Form.vue pages shared across all 12 (see README
        // "Clinical specialty records — now with web forms" for why a
        // generic field-driven form instead of 12 bespoke ones).
        Route::get('/clinical-records', function () {
            return Inertia::render('ClinicalRecords/Index', [
                'entries' => [
                    ['route' => 'complete-denture-records', 'title' => 'Complete Denture Records'],
                    ['route' => 'oral-medicine-charts', 'title' => 'Oral Medicine Charts'],
                    ['route' => 'orthodontics-records', 'title' => 'Orthodontics Records'],
                    ['route' => 'periodontal-charts', 'title' => 'Periodontal Charts'],
                    ['route' => 'prevention-records', 'title' => 'Prevention Records'],
                    ['route' => 'prosthodontics-records', 'title' => 'Prosthodontics Records'],
                    ['route' => 'surgeries', 'title' => 'Surgeries'],
                    ['route' => 'surgery-follow-ups', 'title' => 'Surgery Follow-Ups'],
                    ['route' => 'surgery-images', 'title' => 'Surgery Images'],
                    ['route' => 'surgery-medications', 'title' => 'Surgery Medications'],
                    ['route' => 'treatment-plans', 'title' => 'Treatment Plans'],
                    ['route' => 'treatment-materials', 'title' => 'Treatment Materials'],
                ],
            ]);
        })->name('clinical-records.index');

        // NOTE: the case-sheet resources themselves are NOT registered here.
        // They accept both guards and live in their own group below — see
        // "Case sheets are reachable by both guards" further down.
    });
});

/*
 * Case sheets are reachable by both guards.
 *
 * The original lets *any* logged-in principal open a case sheet
 * (doctor/doctor_auth_check.php: "Allow any logged-in user (doctor_id OR
 * user_id) — individual pages will check permissions") and then decides
 * rights per principal: staff view-only, the owning doctor saves. Ported
 * here as `auth:web,doctor` plus the `case-sheet` middleware, which carries
 * both rules (App\Http\Middleware\EnforceCaseSheetAccess).
 *
 * These were previously registered inside the staff-only
 * `role:super_admin,admin,editor` group, which had the rule exactly
 * backwards: staff could edit any sheet and a doctor — authenticated on the
 * `doctor` guard, therefore not authenticated on `web` — was bounced to the
 * staff login and could never open their own sheet.
 */
Route::middleware(['auth:web,doctor', 'case-sheet'])->group(function () {
    foreach ([
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
        Route::resource($uri, $controller)->parameters([$uri => 'record']);
    }

    // The operative sheet — same rules, and the sheet CaseSheetController
    // falls back to for an unknown case-sheet type. Keeps its own
    // {dentalChart} parameter name, which its controller signatures use.
    Route::resource('dental-charts', DentalChartController::class)->except('destroy');
    Route::delete('/dental-charts/{dentalChart}', [DentalChartController::class, 'destroy'])
        ->name('dental-charts.destroy');
});

require __DIR__.'/auth.php';
