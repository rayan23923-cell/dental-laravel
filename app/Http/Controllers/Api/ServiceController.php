<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Service;
use App\Support\StudentDiscount;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * `register_services` — see `RegisterDayController`'s docblock for why
 * this has no dedicated permission-matrix module (mirrors the original's
 * `settings.edit` gate on `admin/register_settings.php`).
 *
 * `store`/`update` accept a `day_ids` array and `sync()` the
 * `register_day_service_map` pivot in the same request — mirrors
 * `register_settings.php`'s UI (a service name field plus a checkbox grid
 * of days, submitted together as `action=add_service_multiple`).
 */
class ServiceController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(Service::with('days')->orderBy('name')->get());
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255', Rule::unique('register_services', 'name')],
            'price' => ['nullable', 'numeric', 'min:0'],
            // Student discount percentage (2026-10-25); blank keeps the default 50.
            'student_discount_percent' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'day_ids' => ['array'],
            'day_ids.*' => ['integer', 'exists:register_days,id'],
        ]);

        $service = Service::create([
            'name' => $validated['name'],
            'price' => $validated['price'] ?? null,
            'student_discount_percent' => $validated['student_discount_percent'] ?? StudentDiscount::DEFAULT_PERCENT,
        ]);
        $service->days()->sync($validated['day_ids'] ?? []);

        return response()->json($service->load('days'))->setStatusCode(201);
    }

    public function update(Request $request, Service $service): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255', Rule::unique('register_services', 'name')->ignore($service->id)],
            'price' => ['nullable', 'numeric', 'min:0'],
            // Student discount percentage (2026-10-25); blank keeps the default 50.
            'student_discount_percent' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'day_ids' => ['array'],
            'day_ids.*' => ['integer', 'exists:register_days,id'],
        ]);

        $service->update([
            'name' => $validated['name'],
            'price' => $validated['price'] ?? $service->price,
            'student_discount_percent' => $validated['student_discount_percent'] ?? $service->student_discount_percent,
        ]);
        $service->days()->sync($validated['day_ids'] ?? []);

        return response()->json($service->load('days'));
    }

    public function destroy(Service $service): JsonResponse
    {
        $service->delete();

        return response()->json(null, 204);
    }
}
