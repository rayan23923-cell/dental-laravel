<?php

namespace App\Http\Controllers;

use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\Service;
use App\Models\Task;
use App\Services\PatientScreeningException;
use App\Services\PatientScreeningGate;
use App\Support\QrCodeFactory;
use App\Support\LabFeeGate;
use App\Support\RegistrationPaymentState;
use App\Support\StudentDiscount;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use App\Services\PermissionManager;
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
        $permissions = new PermissionManager($request->user());
        $registrations = $this->filteredQuery($request)
            ->with(['service'])
            ->orderByDesc('created_at')
            ->paginate(15)
            ->withQueryString();

        return Inertia::render('PatientRegistrations/Index', [
            'registrations' => $registrations,
            // A from/to date range replaces the old register-day filter
            // (2026-10-14, by request): the days came from settings that
            // were removed. Same as the payments page.
            'services' => Service::orderBy('name')->get(['id', 'name']),
            'filters' => $request->only('search', 'from', 'to', 'service_id', 'archived'),
            // Hides what the desk roles (2026-10-12) can't do here.
            'can' => [
                'archive' => $permissions->can('patients', 'delete'),
                'settings' => $permissions->can('settings', 'edit'),
                'screening' => $permissions->can('patient_screening', 'confirm'),
            ],
        ]);
    }

    /**
     * The registry's search/day/service filters — shared by `index()` and
     * `destroyMany()`'s "delete all" so it deletes exactly what's listed.
     */
    private function filteredQuery(Request $request)
    {
        return PatientRegistration::query()
            // The archive tab (2026-10-12) lists deleted (archived) patients.
            ->when($request->boolean('archived'), fn ($q) => $q->onlyTrashed())
            ->when($request->string('search')->toString(), function ($query, $search) {
                $query->where(function ($q) use ($search) {
                    $q->where('name', 'like', "%{$search}%")
                        ->orWhere('phone', 'like', "%{$search}%");
                });
            })
            ->when($request->date('from'), fn ($q, $from) => $q->whereDate('created_at', '>=', $from))
            ->when($request->date('to'), fn ($q, $to) => $q->whereDate('created_at', '<=', $to))
            ->when($request->integer('service_id'), fn ($q, $id) => $q->where('service_id', $id));
    }

    /**
     * Bulk delete (2026-10-11), same as the doctors table: either the
     * ticked `ids`, or `all` — every registration matching the current
     * filters across all pages. Deleting archives (2026-10-12, soft
     * delete): payments, appointments and task instances keep pointing at
     * the archived row, so money records and their totals are never lost.
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

        return back()->with('success', "تمت أرشفة {$count} تسجيل.");
    }

    /** Brings archived registrations back into the registry (2026-10-12). */
    public function restoreMany(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'ids' => ['required', 'array'],
            'ids.*' => ['integer'],
        ]);

        $count = PatientRegistration::onlyTrashed()->whereIn('id', $validated['ids'])->restore();

        return back()->with('success', "تمت استعادة {$count} تسجيل.");
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
            ->withExists(['payments as lab_paid' => fn ($q) => $q->where('type', Payment::TYPE_LAB)])
            ->get(['id', 'name', 'phone', 'screening_status']);

        return response()->json(['data' => $registrations]);
    }

    public function create(): Response
    {
        // Name, phone and a priced service (2026-10-12): the day is no
        // longer asked, so every configured service is offered.
        return Inertia::render('PatientRegistrations/Create', [
            'services' => Service::orderBy('name')->get(['id', 'name', 'price', 'student_discount_percent']),
            'currency' => \App\Models\ClinicSetting::current()->clinic_currency,
            // An eligible student's stage is picked from these (2026-11-01, by request: 5 by default).
            'stageNames' => StudentDiscount::STAGES,
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
            // The day is no longer asked (2026-10-12); older app builds still send it.
            'register_day_id' => ['nullable', 'integer', 'exists:register_days,id'],
            'service_id' => ['required', 'integer', 'exists:register_services,id'],
            'task_id' => ['nullable', 'integer', 'exists:tasks,id'],
            // Student discount (2026-10-25): not eligible unless ticked.
            // An eligible patient is a student (optional stage) or an
            // employee (optional workplace); older app builds send neither,
            // which counts as a student.
            'discount_eligible' => ['sometimes', 'boolean'],
            'discount_type' => ['nullable', Rule::in(StudentDiscount::TYPES)],
            'discount_stage' => ['nullable', 'string', 'max:100'],
            'discount_workplace' => ['nullable', 'string', 'max:255'],
            // The student's / employee's name (2026-11-01).
            'discount_person_name' => ['nullable', 'string', 'max:255'],
        ]);
        $validated = StudentDiscount::normalize($validated);

        // Payment is mandatory and fixed by the service's price (2026-10-12,
        // by request): the desk no longer types an amount, and an
        // `amount_paid` an older app build still sends is ignored. A
        // service without a price cannot be registered until one is set.
        // An eligible student pays the service's price less its discount.
        $price = StudentDiscount::servicePrice(Service::findOrFail($validated['service_id']), $validated['discount_eligible']);
        if ($price === null) {
            throw ValidationException::withMessages([
                'service_id' => 'هذه الخدمة بلا سعر — حدّد سعرها في إعدادات التسجيل أولاً.',
            ]);
        }
        $amountPaid = (float) $price;

        // Registration is by service only now (2026-10-12): no day check.
        // A day an older app build still sends is stored as before.

        $registration = PatientRegistration::create($validated);

        // The ticket desk takes the service's price at registration, before
        // any lab screening, so it is recorded here directly rather than
        // through PatientScreeningGate.
        if ($amountPaid > 0) {
            Payment::create([
                'patient_registration_id' => $registration->id,
                'amount' => $amountPaid,
                'paid_at' => now(),
                'type' => Payment::TYPE_SERVICE,
            ]);
        }

        // The ticket prints straight away on the list page (2026-10-18, by request).
        return redirect()->route('patient-registrations.index')
            ->with('success', 'تم تسجيل المريض بنجاح.')
            ->with('print_ticket', $registration->id);
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

        // The lab fee is taken with the result (2026-10-12), so the lab
        // prints one paid slip; see LabFeeGate::chargeIfDue().
        DB::transaction(function () use ($patientRegistration, $validated, $request) {
            LabFeeGate::chargeIfDue($patientRegistration);

            $patientRegistration->update([
                'screening_status' => $validated['screening_status'],
                'screening_checked_by' => $request->user()->id,
                'screening_checked_at' => now(),
            ]);
        });

        return $this->stateResponse($patientRegistration->fresh(['service', 'registerDay']));
    }

    private function stateResponse(PatientRegistration $registration): JsonResponse
    {
        return response()->json([
            'data' => RegistrationPaymentState::build($registration, $registration->toArray()),
        ]);
    }
}
