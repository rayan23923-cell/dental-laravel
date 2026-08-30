<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AcademicSession;
use App\Models\Department;
use App\Models\EducationType;
use App\Models\Stage;
use App\Models\User;
use App\Models\UserPermission;
use App\Services\PermissionManager;
use App\Services\ScopeHelper;
use App\Support\PermissionMatrix;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Mirrors App\Http\Controllers\UserPermissionController for the Flutter
 * client. Driven by the same App\Support\PermissionMatrix, so both surfaces
 * expose exactly the original's 11 modules and their per-module actions.
 *
 * **Scope-restriction handling added (2026-08-30)** — previously this
 * docblock said the Flutter admin only manages module/action grants and
 * deliberately left out `App\Services\ScopeHelper` (which departments/
 * stages/education types/academic sessions a user's own account is
 * confined to; empty = unrestricted, sees everything). Found live via a
 * screenshot of the Flutter permissions screen with no such control at
 * all, unlike the web `Permissions/Edit` page — this now mirrors that
 * page's `edit()`/`update()` exactly, reusing the same `ScopeHelper`
 * methods and the same four `user_allowed_*` tables, so a restriction set
 * from either surface is read/written identically.
 */
class UserPermissionController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(
            User::where('role', '!=', 'super_admin')->orderBy('full_name')->get(['id', 'full_name', 'username', 'role'])
        );
    }

    public function show(User $user): JsonResponse
    {
        return response()->json([
            'modules' => PermissionMatrix::forUi(),
            'granted' => UserPermission::where('user_id', $user->id)
                ->where('granted', true)
                ->get(['module', 'permission'])
                ->map(fn ($p) => "{$p->module}.{$p->permission}")
                ->values(),
            'scope_options' => [
                'departments' => Department::orderBy('name')->get(['id', 'name']),
                'stages' => Stage::orderBy('name')->get(['id', 'name']),
                'education_types' => EducationType::orderBy('name')->get(['id', 'name']),
                'academic_sessions' => AcademicSession::orderByDesc('start_date')->get(['id', 'name']),
            ],
            // null on any dimension means "unrestricted" — ScopeHelper's
            // own convention (zero rows = sees everything), not "nothing
            // selected".
            'scope' => [
                'departments' => ScopeHelper::allowedDepartmentIds($user),
                'stages' => ScopeHelper::allowedStageIds($user),
                'education_types' => ScopeHelper::allowedEducationTypeIds($user),
                'academic_sessions' => ScopeHelper::allowedAcademicSessionIds($user),
            ],
        ]);
    }

    public function update(Request $request, User $user): JsonResponse
    {
        $validated = $request->validate([
            'grants' => ['array'],
            'grants.*' => ['string', 'in:'.implode(',', PermissionMatrix::pairs())],
            // Same rule as the web controller: nullable-vs-array, not just
            // an empty array — "leave unrestricted" (omit the field) and
            // "restrict to nothing" (send `[]`, which ScopeHelper also
            // treats as unrestricted per its own "zero rows" rule) don't
            // need to be told apart at this layer.
            'scope' => ['nullable', 'array'],
            'scope.departments' => ['nullable', 'array'],
            'scope.departments.*' => ['integer', 'exists:departments,id'],
            'scope.stages' => ['nullable', 'array'],
            'scope.stages.*' => ['integer', 'exists:stages,id'],
            'scope.education_types' => ['nullable', 'array'],
            'scope.education_types.*' => ['integer', 'exists:education_types,id'],
            'scope.academic_sessions' => ['nullable', 'array'],
            'scope.academic_sessions.*' => ['integer', 'exists:academic_sessions,id'],
        ]);
        $grants = $validated['grants'] ?? [];
        $scope = $validated['scope'] ?? [];

        DB::transaction(function () use ($user, $grants, $scope) {
            foreach (PermissionMatrix::modules() as $module => $definition) {
                foreach (array_keys($definition['permissions']) as $permission) {
                    UserPermission::updateOrCreate(
                        ['user_id' => $user->id, 'module' => $module, 'permission' => $permission],
                        ['granted' => in_array("{$module}.{$permission}", $grants, true)]
                    );

                    PermissionManager::forget($user->id, $module, $permission);
                }
            }

            ScopeHelper::setAllowedDepartments($user, $scope['departments'] ?? []);
            ScopeHelper::setAllowedStages($user, $scope['stages'] ?? []);
            ScopeHelper::setAllowedEducationTypes($user, $scope['education_types'] ?? []);
            ScopeHelper::setAllowedAcademicSessions($user, $scope['academic_sessions'] ?? []);
        });

        return response()->json(['message' => 'Permissions updated.']);
    }
}
