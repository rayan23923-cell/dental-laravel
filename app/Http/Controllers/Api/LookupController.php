<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Department;
use App\Models\EducationType;
use App\Models\Stage;
use App\Services\ScopeHelper;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Reference data (education types, stages, departments) — read (scoped,
 * for populating dropdowns) plus create/update/delete for the Flutter
 * admin screens (2026-08-21). The `index` methods were originally
 * documented "not writable here, managed via the web admin UI"; the
 * write methods below are a straight port of
 * `App\Http\Controllers\{EducationType,Stage,Department}Controller`'s
 * own `store`/`update`/`destroy` (same validation, same models) —
 * `routes/api.php` gates them identically to their web counterparts too
 * (`role:super_admin,admin` for education types; that plus
 * `permission:stages,*`/`permission:departments,*` for the other two —
 * see the route definitions and `web.php`'s own comment on why
 * `departments` specifically carries a permission gate the matrix UI had
 * silently never enforced before).
 *
 * Scoped the same way as the equivalent web admin lists (see
 * App\Services\ScopeHelper) so a scoped staff user's Flutter session can't
 * see more than their web session can.
 */
class LookupController extends Controller
{
    public function educationTypes(Request $request): JsonResponse
    {
        $query = ScopeHelper::scopeEducationTypes(EducationType::query(), $request->user());

        return response()->json($query->orderBy('name')->get(['id', 'name']));
    }

    public function storeEducationType(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100', Rule::unique('education_types', 'name')],
        ]);

        return response()->json(EducationType::create($validated))->setStatusCode(201);
    }

    public function updateEducationType(Request $request, EducationType $educationType): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100', Rule::unique('education_types', 'name')->ignore($educationType->id)],
        ]);

        $educationType->update($validated);

        return response()->json($educationType);
    }

    public function destroyEducationType(EducationType $educationType): JsonResponse
    {
        $educationType->delete();

        return response()->json(null, 204);
    }

    public function stages(Request $request): JsonResponse
    {
        $query = ScopeHelper::scopeStages(Stage::query(), $request->user());

        return response()->json($query->orderBy('name')->get(['id', 'name', 'education_type_id']));
    }

    public function storeStage(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'education_type_id' => ['nullable', 'exists:education_types,id'],
        ]);

        return response()->json(Stage::create($validated))->setStatusCode(201);
    }

    public function updateStage(Request $request, Stage $stage): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'education_type_id' => ['nullable', 'exists:education_types,id'],
        ]);

        $stage->update($validated);

        return response()->json($stage);
    }

    public function destroyStage(Stage $stage): JsonResponse
    {
        $stage->delete();

        return response()->json(null, 204);
    }

    public function departments(Request $request): JsonResponse
    {
        $query = Department::query();
        $query = ScopeHelper::scopeDepartments($query, $request->user(), 'id');
        $query = ScopeHelper::scopeEducationTypes($query, $request->user(), 'education_type_id');
        $query = ScopeHelper::scopeStages($query, $request->user(), 'stage_id');

        return response()->json($query->orderBy('name')->get(['id', 'name', 'stage_id', 'education_type_id']));
    }

    public function storeDepartment(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'stage_id' => ['nullable', 'exists:stages,id'],
            'education_type_id' => ['nullable', 'exists:education_types,id'],
        ]);

        return response()->json(Department::create($validated))->setStatusCode(201);
    }

    public function updateDepartment(Request $request, Department $department): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'stage_id' => ['nullable', 'exists:stages,id'],
            'education_type_id' => ['nullable', 'exists:education_types,id'],
        ]);

        $department->update($validated);

        return response()->json($department);
    }

    public function destroyDepartment(Department $department): JsonResponse
    {
        $department->delete();

        return response()->json(null, 204);
    }
}
