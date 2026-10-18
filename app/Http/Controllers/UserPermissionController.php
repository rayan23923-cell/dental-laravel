<?php

namespace App\Http\Controllers;

use App\Models\AcademicSession;
use App\Models\Department;
use App\Models\EducationType;
use App\Models\Stage;
use App\Models\User;
use App\Models\UserPermission;
use App\Services\PermissionManager;
use App\Services\ScopeHelper;
use App\Support\PermissionMatrix;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Grants/revokes rows in `user_permissions` — the table PermissionManager
 * actually checks (see App\Services\PermissionManager docblock for why
 * this is the real ACL and `roles`/`permissions`/`role_permissions` are
 * not) — and, separately, a user's access-scope restrictions
 * (App\Services\ScopeHelper): which departments/stages/education
 * types/academic years their own account is confined to.
 *
 * The module/action matrix lives in App\Support\PermissionMatrix, copied
 * verbatim from the original's own definition — including its per-module
 * action sets, which an earlier version of this port flattened into a
 * uniform view/create/edit/delete/export grid (see README).
 *
 * The scope section is new here, not carried over from an earlier version:
 * `ScopeHelper::setAllowedDepartments()`/`setAllowedStages()`/
 * `setAllowedEducationTypes()` already existed (the original's own
 * `save_scope_permissions.php` equivalent) but were never actually called
 * from anywhere — confirmed by a repo-wide search — so a scope restriction
 * could never be set through this app at all, on any of the four
 * dimensions. Wired up here, all four together, rather than adding only
 * the academic-session one and leaving its three siblings still
 * unreachable.
 */
class UserPermissionController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('Permissions/Index', [
            'users' => User::where('role', '!=', 'super_admin')
                ->orderBy('full_name')
                ->get(['id', 'full_name', 'username', 'role']),
        ]);
    }

    public function edit(User $user): Response
    {
        $granted = UserPermission::where('user_id', $user->id)
            ->where('granted', true)
            ->get(['module', 'permission'])
            ->map(fn ($p) => "{$p->module}.{$p->permission}")
            ->all();

        return Inertia::render('Permissions/Edit', [
            'targetUser' => $user,
            'modules' => PermissionMatrix::forUi(),
            'granted' => $granted,
            // Each option carries its parent so the screen can cascade:
            // education type → stages → departments (2026-10-14).
            'scopeOptions' => (function () {
                $o = ScopeHelper::options();

                return [
                    'departments' => $o['departments'],
                    'stages' => $o['stages'],
                    'educationTypes' => $o['education_types'],
                    'academicSessions' => $o['academic_sessions'],
                ];
            })(),
            // Picked ids, or null when none are picked; see the API twin
            // for the all* flags ("الكل", 2026-10-18).
            'scope' => [
                'departments' => ScopeHelper::chosenDepartmentIds($user),
                'stages' => ScopeHelper::chosenStageIds($user),
                'educationTypes' => ScopeHelper::chosenTopLevel($user, 'education_types'),
                'academicSessions' => ScopeHelper::chosenTopLevel($user, 'academic_sessions'),
                'allEducationTypes' => (bool) $user->scope_all_education_types,
                'allAcademicSessions' => (bool) $user->scope_all_academic_sessions,
            ],
        ]);
    }

    public function update(Request $request, User $user): RedirectResponse
    {
        $validated = $request->validate([
            'grants' => ['array'],
            // Only pairs the matrix actually defines are accepted — a
            // client can't invent a module/permission combination.
            'grants.*' => ['string', 'in:'.implode(',', PermissionMatrix::pairs())],
            // Each scope field is nullable-vs-array, not just an empty
            // array, so "leave unrestricted" (send nothing) and "restrict
            // to nothing" (send an empty list, which ScopeHelper would also
            // treat as unrestricted per its own "zero rows" rule — there is
            // no way to express "allowed to see nothing" and that's
            // intentional) don't need to be told apart at this layer.
            ...ScopeHelper::rules(),
        ]);
        $grants = $validated['grants'] ?? [];
        $scope = $validated['scope'] ?? [];

        DB::transaction(function () use ($user, $grants, $scope) {
            PermissionManager::syncGrants($user, $grants);
            ScopeHelper::saveScope($user, $scope);
        });

        return redirect()->route('permissions.index')->with('success', "Permissions updated for {$user->full_name}.");
    }
}
