<?php

namespace App\Http\Controllers;

use App\Models\PatientRegistration;
use App\Models\RegisterDay;
use App\Models\Service;
use App\Models\Task;
use App\Services\PatientScreeningException;
use App\Services\PatientScreeningGate;
use App\Support\QrCodeFactory;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response as HttpResponse;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Web (Inertia) side of the reception-desk patient registration feature —
 * see `App\Models\PatientRegistration`'s docblock for why this is
 * deliberately separate from `PatientController`. Mirrors
 * `admin/patient_register.php`'s day-first cascading UX: pick a day, the
 * service list filters to what's offered that day.
 */
class PatientRegistrationController extends Controller
{
    public function index(Request $request): Response
    {
        $registrations = $this->filteredQuery($request)
            ->with(['service', 'registerDay'])
            ->orderByDesc('created_at')
            ->paginate(15)
            ->withQueryString();

        return Inertia::render('PatientRegistrations/Index', [
            'registrations' => $registrations,
            'days' => RegisterDay::with('services')->orderBy('sort_order')->orderBy('name')->get(),
            'filters' => $request->only('search', 'register_day_id', 'service_id'),
        ]);
    }

    /**
     * The registry's search/day/service filters — shared by `index()` and
     * `destroyMany()`'s "delete all" so it deletes exactly what's listed.
     */
    private function filteredQuery(Request $request)
    {
        return PatientRegistration::query()
            ->when($request->string('search')->toString(), function ($query, $search) {
                $query->where(function ($q) use ($search) {
                    $q->where('name', 'like', "%{$search}%")
                        ->orWhere('phone', 'like', "%{$search}%");
                });
            })
            ->when($request->integer('register_day_id'), fn ($q, $id) => $q->where('register_day_id', $id))
            ->when($request->integer('service_id'), fn ($q, $id) => $q->where('service_id', $id));
    }

    /**
     * Bulk delete (2026-10-11), same as the doctors table: either the
     * ticked `ids`, or `all` — every registration matching the current
     * filters across all pages. Payments/appointments/task instances keep
     * their stored registration id (there are no foreign keys), so money
     * records are never lost with the registration.
     */
    public function destroyMany(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'all' => ['sometimes', 'boolean'],
            'ids' => ['required_without:all', 'array'],
            'ids.*' => ['integer'],
        ]);

        $query = ($validated['all'] ?? false)
            ? $this->filteredQuery($request)
            : PatientRegistration::whereIn('id', $validated['ids']);

        $count = $query->delete();

        return back()->with('success', "تم حذف {$count} تسجيل.");
    }

    /**
     * Lightweight autocomplete for the payment form's "ابحث عن مريض"
     * field (2026-08-26) — `Payments/Create.vue` previously loaded every
     * registration into one giant `<select>`, unusable once the table has
     * more than a handful of rows. Same search columns as `index()`,
     * capped instead of paginated since this only ever backs a dropdown.
     */
    public function search(Request $request): JsonResponse
    {
        $search = $request->string('q')->toString();

        if ($search === '') {
            return response()->json(['data' => []]);
        }

        // `screening_status` added (2026-08-29) so a search-selected match
        // (not just a scanned one) can also be checked against
        // `PatientScreeningGate` client-side before payment — see
        // Payments/Create.vue.
        $registrations = PatientRegistration::where('name', 'like', "%{$search}%")
            ->orWhere('phone', 'like', "%{$search}%")
            ->orderByDesc('created_at')
            ->limit(10)
            ->get(['id', 'name', 'phone', 'screening_status']);

        return response()->json(['data' => $registrations]);
    }

    public function create(): Response
    {
        return Inertia::render('PatientRegistrations/Create', [
            // `tasks:id` — day-governed diagnosis (see RegisterDay::tasks()'s
            // docblock); the form narrows the task list to a selected day's
            // configured tasks, when that day has any configured at all.
            'days' => RegisterDay::with(['services', 'tasks:id'])->orderBy('sort_order')->orderBy('name')->get(),
            // "التشخيص" picker — still not gated by stage/education type
            // (see PatientRegistration::task()'s docblock), only by day now.
            'tasks' => Task::with('stage.educationType')->orderBy('title')->get(['id', 'title', 'stage_id']),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        // A blank select submits '', not null — same bug class fixed
        // elsewhere this session (Doctor::nfc_tag_id, Appointment's
        // patient_registration_id): without this, leaving "التشخيص"
        // unset would fail `exists:tasks,id` against an empty string.
        if ($request->input('task_id') === '') {
            $request->merge(['task_id' => null]);
        }

        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'phone' => ['required', 'string', 'max:20'],
            'register_day_id' => ['required', 'integer', 'exists:register_days,id'],
            'service_id' => ['required', 'integer', 'exists:register_services,id'],
            'task_id' => ['nullable', 'integer', 'exists:tasks,id'],
        ]);

        $offeredOnDay = Service::whereKey($validated['service_id'])
            ->whereHas('days', fn ($q) => $q->where('register_days.id', $validated['register_day_id']))
            ->exists();

        if (! $offeredOnDay) {
            throw ValidationException::withMessages([
                'service_id' => 'هذه الخدمة غير متاحة في اليوم المحدد.',
            ]);
        }

        // Day-governed diagnosis — see RegisterDay::tasks()'s docblock.
        // Opt-in per day: only enforced once a day has at least one task
        // configured, so an unconfigured day stays fully open (no
        // existing registration flow breaks the moment this ships).
        if (! empty($validated['task_id'])) {
            $dayHasTaskRules = RegisterDay::whereKey($validated['register_day_id'])->whereHas('tasks')->exists();
            if ($dayHasTaskRules) {
                $taskOfferedOnDay = Task::whereKey($validated['task_id'])
                    ->whereHas('days', fn ($q) => $q->where('register_days.id', $validated['register_day_id']))
                    ->exists();

                if (! $taskOfferedOnDay) {
                    throw ValidationException::withMessages([
                        'task_id' => 'هذا التشخيص غير متاح في اليوم المحدد.',
                    ]);
                }
            }
        }

        PatientRegistration::create($validated);

        return redirect()->route('patient-registrations.index')->with('success', 'تم تسجيل المريض بنجاح.');
    }

    /**
     * Same payload/generation as
     * `Api\PatientRegistrationQrController::show()` — for on-screen display
     * from the registration page (the desk QR is also printed on the
     * thermal ticket, but staff need to see it without paper too).
     */
    public function qr(PatientRegistration $patientRegistration): HttpResponse
    {
        return QrCodeFactory::pngResponse(
            QrCodeFactory::payload('patient_registration', $patientRegistration->id),
        );
    }

    /**
     * Web twin of `Api\PatientRegistrationQrController::scan()`, for
     * `Components/QrScanner.vue` at the payment desk.
     */
    public function scan(Request $request): JsonResponse
    {
        $request->validate(['payload' => ['required', 'string']]);

        $decoded = json_decode($request->string('payload'), true);

        if (! is_array($decoded) || ($decoded['type'] ?? null) !== 'patient_registration' || empty($decoded['id'])) {
            return response()->json(['message' => 'رمز غير صالح — هذا ليس رمز تسجيل مريض.'], 422);
        }

        $registration = PatientRegistration::with(['service', 'registerDay'])->find($decoded['id']);

        if (! $registration) {
            return response()->json(['message' => 'التسجيل غير موجود.'], 404);
        }

        return $this->stateResponse($registration);
    }

    /**
     * Doctor-only twin of `scan()` above, for the case-sheet
     * "مسح رمز المريض" patient-autofill button (2026-08-28) —
     * `scan()`/`Api\PatientRegistrationQrController::scan()` are both
     * gated by `permission:patients,view`, a staff-only concept
     * (`EnsureUserHasPermission` explicitly rejects a Doctor principal
     * rather than passing it to `PermissionManager`), so a doctor's own
     * session could never reach either — found live via a real scan
     * attempt on-device ("لا تملك صلاحية لهذا الإجراء"). This route sits
     * outside that gate entirely (see the doctor-only group in
     * `routes/web.php`) and additionally enforces `PatientScreeningGate`:
     * a patient who hasn't been lab-screened yet, or came back flagged,
     * must not be readable here either — the user's own explicit
     * requirement, matching the same gate already applied to payment and
     * task-starting.
     */
    public function scanForCaseSheet(Request $request): JsonResponse
    {
        abort_unless(Auth::guard('doctor')->check(), 403);

        $request->validate(['payload' => ['required', 'string']]);

        $decoded = json_decode($request->string('payload'), true);

        if (! is_array($decoded) || ($decoded['type'] ?? null) !== 'patient_registration' || empty($decoded['id'])) {
            return response()->json(['message' => 'رمز غير صالح — هذا ليس رمز تسجيل مريض.'], 422);
        }

        $registration = PatientRegistration::with(['service', 'registerDay'])->find($decoded['id']);

        if (! $registration) {
            return response()->json(['message' => 'التسجيل غير موجود.'], 404);
        }

        try {
            PatientScreeningGate::ensureClear($registration);
        } catch (PatientScreeningException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return $this->stateResponse($registration);
    }

    /**
     * Web twin of `Api\PatientRegistrationQrController::confirmScreening()`
     * — see that method's docblock and `PatientScreeningGate`.
     */
    public function confirmScreening(Request $request, PatientRegistration $patientRegistration): JsonResponse
    {
        $validated = $request->validate([
            'screening_status' => ['required', Rule::in(['clear', 'flagged'])],
        ]);

        $patientRegistration->update([
            'screening_status' => $validated['screening_status'],
            'screening_checked_by' => $request->user()->id,
            'screening_checked_at' => now(),
        ]);

        return $this->stateResponse($patientRegistration->fresh(['service', 'registerDay']));
    }

    private function stateResponse(PatientRegistration $registration): JsonResponse
    {
        $payments = $registration->payments()->orderByDesc('paid_at')->get();

        return response()->json([
            'data' => [
                'registration' => $registration,
                'payments' => $payments->map(fn ($p) => [
                    'id' => $p->id,
                    'amount' => $p->amount,
                    'paid_by' => $p->paid_by,
                    'paid_at' => $p->paid_at,
                ])->values(),
                'total_paid' => (float) $payments->sum('amount'),
                'is_paid' => $payments->isNotEmpty(),
            ],
        ]);
    }
}
