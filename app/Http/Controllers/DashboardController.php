<?php

namespace App\Http\Controllers;

use App\Models\Department;
use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Patient;
use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\ClinicSetting;
use App\Support\PaymentStats;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\User;
use App\Services\AcademicSessionHelper;
use App\Services\PermissionManager;
use Illuminate\Http\JsonResponse;
use App\Support\RolePresets;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Admin dashboard — port of dental_clinics2/admin/dashboard.php.
 *
 * Reproduces its real structure: three headline counters (doctors /
 * patients / tasks), a done-vs-not-done task breakdown, "أحدث الأطباء" and
 * "أحدث المراجعين" lists, quick-access cards, and the
 * "المهام المطلوبة لكل قسم ومرحلة حسب نوع الدراسة" section that loads on
 * demand per education type (`ajax/dashboard_tasks_by_dept.php`).
 *
 * Deliberately not ported from that page:
 *  - "الدخول كطبيب" (impersonation) — orphaned in the original, see README;
 *  - "النسخ الاحتياطي" — the MikroTik/backup feature, out of scope by request;
 *  - "تسجيل مريض جديد" pointing at patients_simple/patients_admin, the
 *    separate intake tables this rebuild deliberately doesn't use (its
 *    patient counter therefore counts `patients`, the table the rest of the
 *    app actually references, rather than summing three unrelated tables
 *    the way the original does).
 */
class DashboardController extends Controller
{
    public function index(Request $request): Response|RedirectResponse
    {
        $user = $request->user();

        // Desk roles (2026-10-12) land on their own page: the dashboard's
        // figures and links are outside what they can open.
        if (RolePresets::isDeskRole($user->role)) {
            return redirect()->route(RolePresets::HOME_ROUTES[$user->role]);
        }

        return Inertia::render('Dashboard', $this->dashboardData($user));
    }

    /**
     * The dashboard's figures, shared with the app's
     * Api\DashboardController (2026-10-17) so both show the same numbers.
     */
    public function dashboardData(User $user): array
    {
        $permissions = new PermissionManager($user);
        // Payments routes are role-gated (super_admin/admin/editor), not
        // permission-gated; mirror that so the dashboard never links past it.
        $canPayments = in_array($user->role, ['super_admin', 'admin', 'editor'], true);
        $session = AcademicSessionHelper::resolve();
        $sessionId = $session?->id;

        $tasks = Task::query()
            ->when($sessionId, fn ($q) => $q->where(fn ($q2) => $q2
                ->where('academic_session_id', $sessionId)
                ->orWhereNull('academic_session_id')));

        return [
            'stats' => [
                'doctors' => Doctor::count(),
                'patients' => Patient::count(),
                'registrations' => PatientRegistration::count(),
                'registrations_today' => PatientRegistration::where('created_at', '>=', now()->startOfDay())->count(),
                'tasks' => (clone $tasks)->count(),
                // `tasks.done` is the original's own per-task flag.
                'tasks_done' => (clone $tasks)->where('done', true)->count(),
                'tasks_not_done' => (clone $tasks)->where('done', false)->count(),
                'instances_completed' => TaskInstance::where('status', 'completed')->count(),
                'instances_assigned' => TaskInstance::where('status', 'assigned')->count(),
                'instances_pending' => TaskInstance::where('status', 'pending')->count(),
            ],
            'latestDoctors' => Doctor::with('educationType:id,name')
                ->latest('id')->limit(5)
                ->get(['id', 'name', 'education_type_id', 'created_at'])
                ->map(fn ($d) => [
                    'id' => $d->id,
                    'name' => $d->name,
                    'education_type' => $d->educationType?->name,
                    'created_at' => $d->created_at,
                ]),
            // "أحدث المراجعين" comes from the patient registry (2026-10-13,
            // by request) so each one opens in سجل المرضى, rather than from
            // the separate `patients` table nothing on the dashboard links to.
            'latestPatients' => PatientRegistration::with('service:id,name')
                ->latest('id')->limit(5)
                ->get(['id', 'name', 'phone', 'service_id', 'screening_status', 'created_at'])
                ->map(fn ($r) => [
                    'id' => $r->id,
                    'name' => $r->name,
                    'phone' => $r->phone,
                    'service' => $r->service?->name,
                    'screening_status' => $r->screening_status,
                    'created_at' => $r->created_at,
                ]),
            // Payments on the dashboard (2026-10-13, by request).
            'latestPayments' => $canPayments
                ? Payment::with(['appointment:id,full_name', 'patientRegistration:id,name'])
                    ->latest('paid_at')->limit(5)
                    ->get()
                    ->map(fn ($p) => [
                        'id' => $p->id,
                        'name' => $p->patientRegistration?->name ?? $p->appointment?->full_name,
                        'amount' => (float) $p->amount,
                        'source' => $p->type === Payment::TYPE_LAB ? 'lab' : ($p->appointment_id ? 'appointment' : 'registration'),
                        'paid_at' => $p->paid_at,
                    ])
                : [],
            'income' => $canPayments ? (new PaymentStats())->periods() : null,
            'currency' => ClinicSetting::current()->clinic_currency,
            'educationTypes' => EducationType::orderBy('name')->get(['id', 'name']),
            // New — the dashboard previously showed no active-year
            // indicator anywhere, unlike Doctors/Groups/Tasks.
            'currentSession' => $session?->only('id', 'name'),
            // Drives which quick-access cards are shown, so the dashboard
            // doesn't offer links the user's grants would reject.
            'can' => [
                'task_progress' => $permissions->can('task_progress', 'view'),
                'doctors' => $permissions->can('doctors', 'view'),
                'patients' => $permissions->can('patients', 'view'),
                'settings' => $permissions->can('settings', 'view'),
                // The infectious-disease screening feature (2026-08-25)
                // had no dashboard entry point at all — added (2026-08-26)
                // alongside the Flutter dashboard's matching shortcut.
                'patient_screening' => $permissions->can('patient_screening', 'confirm'),
                'payments' => $canPayments,
            ],
        ];
    }

    /**
     * Port of ajax/dashboard_tasks_by_dept.php — required tasks per
     * department and stage for one education type, loaded on demand when
     * the dashboard's education-type select changes.
     */
    public function tasksByEducationType(EducationType $educationType): JsonResponse
    {
        $sessionId = AcademicSessionHelper::resolveId();

        $departments = Department::whereHas('stage', fn ($q) => $q->where('education_type_id', $educationType->id))
            ->with('stage:id,name')
            ->orderBy('name')
            ->get();

        $rows = $departments->map(function ($department) use ($sessionId) {
            $tasks = Task::where('department_id', $department->id)
                ->when($sessionId, fn ($q) => $q->where(fn ($q2) => $q2
                    ->where('academic_session_id', $sessionId)
                    ->orWhereNull('academic_session_id')))
                ->withCount([
                    'instances as completed' => fn ($q) => $q->where('status', 'completed'),
                ])
                ->orderBy('title')
                ->get();

            return [
                'department' => $department->name,
                'stage' => $department->stage?->name,
                'required' => (int) $tasks->sum('required_count'),
                'completed' => (int) $tasks->sum('completed'),
                'tasks' => $tasks->map(fn ($t) => [
                    'id' => $t->id,
                    'title' => $t->title,
                    'required' => (int) $t->required_count,
                    'completed' => (int) $t->completed,
                    'remaining' => max(0, (int) $t->required_count - (int) $t->completed),
                ])->values(),
            ];
        })->filter(fn ($row) => $row['tasks']->isNotEmpty())->values();

        return response()->json(['departments' => $rows]);
    }
}
