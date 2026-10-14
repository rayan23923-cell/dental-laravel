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
            // Each option carries its parent so the screen can cascade:
            // education type → stages → departments (2026-10-14).
            'scope_options' => ScopeHelper::options(),
            // null on any dimension means "unrestricted" (nothing picked).
            'scope' => [
                'departments' => ScopeHelper::chosenDepartmentIds($user),
                'stages' => ScopeHelper::chosenStageIds($user),
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
            ...ScopeHelper::rules(),
        ]);
        $grants = $validated['grants'] ?? [];
        $scope = $validated['scope'] ?? [];

        DB::transaction(function () use ($user, $grants, $scope) {
            PermissionManager::syncGrants($user, $grants);
            ScopeHelper::saveScope($user, $scope);
        });

        return response()->json(['message' => 'Permissions updated.']);
    }
}
