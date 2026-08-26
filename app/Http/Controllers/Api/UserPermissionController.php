<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Models\UserPermission;
use App\Services\PermissionManager;
use App\Support\PermissionMatrix;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Mirrors App\Http\Controllers\UserPermissionController for the Flutter
 * client. Driven by the same App\Support\PermissionMatrix, so both surfaces
 * expose exactly the original's 11 modules and their per-module actions.
 *
 * Deliberately does not mirror the web controller's scope-restriction
 * handling (`App\Services\ScopeHelper` — which departments/stages/
 * education types/academic sessions a user's own account is confined to):
 * a separate 4-dimension multi-select feature, out of scope for this pass.
 * The Flutter admin only manages module/action grants.
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
        ]);
    }

    public function update(Request $request, User $user): JsonResponse
    {
        $validated = $request->validate([
            'grants' => ['array'],
            'grants.*' => ['string', 'in:'.implode(',', PermissionMatrix::pairs())],
        ]);
        $grants = $validated['grants'] ?? [];

        DB::transaction(function () use ($user, $grants) {
            foreach (PermissionMatrix::modules() as $module => $definition) {
                foreach (array_keys($definition['permissions']) as $permission) {
                    UserPermission::updateOrCreate(
                        ['user_id' => $user->id, 'module' => $module, 'permission' => $permission],
                        ['granted' => in_array("{$module}.{$permission}", $grants, true)]
                    );

                    PermissionManager::forget($user->id, $module, $permission);
                }
            }
        });

        return response()->json(['message' => 'Permissions updated.']);
    }
}
