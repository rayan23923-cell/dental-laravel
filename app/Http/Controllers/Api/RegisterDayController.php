<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\RegisterDay;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * `register_days` — reference data for the reception-desk patient
 * registration feature (`PatientRegistration`). `index()` returns each
 * day with its offered `services` **and** day-governed `tasks`
 * ("التشخيص", see `RegisterDay::tasks()`'s docblock) nested, in one call
 * — what both the registration form's day-first cascading picker and the
 * settings screen's day list need.
 *
 * Gated the same way the original app gates `admin/register_settings.php`
 * (`$perm->requirePermission('settings', 'edit')`) — confirmed by reading
 * that file directly rather than inventing a new permission-matrix
 * module; `PermissionMatrix` deliberately mirrors the original's module
 * list exactly (see its own docblock), and the original has no dedicated
 * module for this feature at all.
 */
class RegisterDayController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(
            RegisterDay::with(['services', 'tasks:id,title'])->orderBy('sort_order')->orderBy('name')->get()
        );
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100', Rule::unique('register_days', 'name')],
            'sort_order' => ['nullable', 'integer'],
        ]);

        $day = RegisterDay::create($validated);

        return response()->json($day)->setStatusCode(201);
    }

    public function update(Request $request, RegisterDay $registerDay): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100', Rule::unique('register_days', 'name')->ignore($registerDay->id)],
            'sort_order' => ['nullable', 'integer'],
        ]);

        $registerDay->update($validated);

        return response()->json($registerDay);
    }

    public function destroy(RegisterDay $registerDay): JsonResponse
    {
        $registerDay->delete();

        return response()->json(null, 204);
    }
}
