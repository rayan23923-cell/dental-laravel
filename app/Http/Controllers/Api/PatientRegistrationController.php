<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\PatientRegistrationResource;
use App\Models\PatientRegistration;
use App\Models\RegisterDay;
use App\Models\Service;
use App\Models\Task;
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
        $registrations = PatientRegistration::with(['service', 'registerDay'])
            ->when($request->string('search')->toString(), function ($query, $search) {
                $query->where(function ($q) use ($search) {
                    $q->where('name', 'like', "%{$search}%")
                        ->orWhere('phone', 'like', "%{$search}%");
                });
            })
            ->when($request->integer('register_day_id'), fn ($q, $id) => $q->where('register_day_id', $id))
            ->when($request->integer('service_id'), fn ($q, $id) => $q->where('service_id', $id))
            ->orderByDesc('created_at')
            ->paginate(15);

        return PatientRegistrationResource::collection($registrations)->response();
    }

    public function store(Request $request): JsonResponse
    {
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

        // The original enforces this server-side too
        // (`patient_register.php:76-89`, checking the selected service
        // against that day's allow-list) — done here with a real query
        // against the pivot instead of a PHP array built from an embedded
        // JSON map.
        $offeredOnDay = Service::whereKey($validated['service_id'])
            ->whereHas('days', fn ($q) => $q->where('register_days.id', $validated['register_day_id']))
            ->exists();

        if (! $offeredOnDay) {
            throw ValidationException::withMessages([
                'service_id' => ['هذه الخدمة غير متاحة في اليوم المحدد.'],
            ]);
        }

        // Day-governed diagnosis — see RegisterDay::tasks()'s docblock.
        // Opt-in per day, same reasoning as the web twin
        // (PatientRegistrationController::store()).
        if (! empty($validated['task_id'])) {
            $dayHasTaskRules = RegisterDay::whereKey($validated['register_day_id'])->whereHas('tasks')->exists();
            if ($dayHasTaskRules) {
                $taskOfferedOnDay = Task::whereKey($validated['task_id'])
                    ->whereHas('days', fn ($q) => $q->where('register_days.id', $validated['register_day_id']))
                    ->exists();

                if (! $taskOfferedOnDay) {
                    throw ValidationException::withMessages([
                        'task_id' => ['هذا التشخيص غير متاح في اليوم المحدد.'],
                    ]);
                }
            }
        }

        $registration = PatientRegistration::create($validated);

        // `fresh()`, not `load()` — `screening_status` is a DB-level
        // default (`'pending'`) never passed to `create()`, so the
        // in-memory model wouldn't reflect it without re-fetching (found
        // testing the infectious-disease screening feature, 2026-08-26).
        return (new PatientRegistrationResource($registration->fresh(['service', 'registerDay', 'task.stage.educationType'])))
            ->response()->setStatusCode(201);
    }
}
