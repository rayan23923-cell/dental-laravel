<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\PatientRegistrationResource;
use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\RegisterDay;
use App\Models\Service;
use App\Support\StudentDiscount;
use App\Models\Task;
use App\Models\User;
use App\Services\PermissionManager;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/**
 * `patients_simple` — the reception-desk "register a new patient with a
 * service + day" flow. See `App\Models\PatientRegistration`'s docblock:
 * deliberately separate from `Api\PatientController` (the `patients`
 * table / doctor-task-tracking concept).
 *
 * Gated on the *existing* `patients` permission module
 * (`permission:patients,view`/`permission:patients,create`) rather than a
 * new one — confirmed by reading `admin/patient_register.php` directly:
 * the original app gates this exact screen with
 * `$perm->requirePermission('patients', 'create')`, reusing the same
 * module as the other patient-adding screen even though the underlying
 * table differs. Matched here rather than inventing a new module, per
 * `PermissionMatrix`'s own "mirror the original's module list exactly"
 * rule.
 */
class PatientRegistrationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $registrations = $this->filteredQuery($request)
            ->with(['service', 'registerDay'])
            ->orderByDesc('created_at')
            ->paginate(15);

        // What the app may offer here (2026-10-17), as the web page's
        // `can.archive`: archiving and restoring need `patients,delete`.
        $user = $request->user();
        $canArchive = $user instanceof User && (new PermissionManager($user))->can('patients', 'delete');

        return PatientRegistrationResource::collection($registrations)
            ->additional(['can' => ['archive' => $canArchive]])
            ->response();
    }

    /**
     * Search / date range / service filters, plus the archive tab
     * (2026-10-17, as the web registry's): `archived=1` lists the archived
     * (soft-deleted) registrations instead. Shared by `index()` and
     * `destroyMany()`'s "archive all" so it archives exactly what's listed.
     */
    private function filteredQuery(Request $request): Builder
    {
        return PatientRegistration::query()
            ->when($request->boolean('archived'), fn ($q) => $q->onlyTrashed())
            ->when($request->string('search')->toString(), function ($query, $search) {
                $query->where(function ($q) use ($search) {
                    $q->where('name', 'like', "%{$search}%")
                        ->orWhere('phone', 'like', "%{$search}%");
                });
            })
            ->when($request->integer('register_day_id'), fn ($q, $id) => $q->where('register_day_id', $id))
            // Date range (2026-10-14), replacing the day filter in the apps.
            ->when($request->date('from'), fn ($q, $from) => $q->whereDate('created_at', '>=', $from))
            ->when($request->date('to'), fn ($q, $to) => $q->whereDate('created_at', '<=', $to))
            ->when($request->integer('service_id'), fn ($q, $id) => $q->where('service_id', $id));
    }

    /**
     * Bulk archive (2026-10-17), the web `destroyMany()`: the ticked `ids`,
     * or `all` — every registration matching the filters. Archiving is a
     * soft delete, so payments and their totals are kept.
     */
    public function destroyMany(Request $request): JsonResponse
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

        return response()->json(['count' => $count, 'message' => "تمت أرشفة {$count} تسجيل."]);
    }

    /** Brings archived registrations back (2026-10-17), the web `restoreMany()`. */
    public function restoreMany(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'ids' => ['required', 'array'],
            'ids.*' => ['integer'],
        ]);

        $count = PatientRegistration::onlyTrashed()->whereIn('id', $validated['ids'])->restore();

        return response()->json(['count' => $count, 'message' => "تمت استعادة {$count} تسجيل."]);
    }

    public function store(Request $request): JsonResponse
    {
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
            'discount_eligible' => ['sometimes', 'boolean'],
        ]);
        $validated['discount_eligible'] = (bool) ($validated['discount_eligible'] ?? false);

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

        // The original enforces this server-side too
        // (`patient_register.php:76-89`, checking the selected service
        // against that day's allow-list) — done here with a real query
        // against the pivot instead of a PHP array built from an embedded
        // JSON map.
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

        // `fresh()`, not `load()` — `screening_status` is a DB-level
        // default (`'pending'`) never passed to `create()`, so the
        // in-memory model wouldn't reflect it without re-fetching (found
        // testing the infectious-disease screening feature, 2026-08-26).
        return (new PatientRegistrationResource($registration->fresh(['service', 'registerDay', 'task.stage.educationType'])))
            ->response()->setStatusCode(201);
    }
}
