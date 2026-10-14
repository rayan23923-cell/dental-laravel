<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\User;
use App\Support\RolePresets;
use App\Services\CredentialMailer;
use App\Services\PermissionManager;
use App\Services\ScopeHelper;
use App\Support\PermissionMatrix;
use Illuminate\Support\Facades\DB;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;

/**
 * Creating a new staff/admin account — genuinely new, not a port. The web
 * app never had this either: the only place `User::create()` happened was
 * Laravel Breeze's public, logged-out self-registration screen (hardcodes
 * `role: 'editor'`, no role choice). `Api\UserPermissionController`
 * (permissions_admin's backend) only edits permissions of users that
 * already exist.
 *
 * `role` can never be `super_admin` here — `UserPermissionController::index()`
 * already excludes `super_admin` accounts from the manageable list
 * (`User::where('role', '!=', 'super_admin')`), so this mirrors that same
 * "super_admin accounts aren't touched through this admin surface" rule at
 * creation time too, rather than letting a plain `admin` mint a new
 * `super_admin` and immediately break that assumption.
 */
class UserController extends Controller
{
    /**
     * What the add-user form needs to show the permissions editor before
     * the account exists (2026-10-14, by request): the matrix, the scope
     * options, and each role's pre-ticked grants.
     */
    public function formOptions(): JsonResponse
    {
        return response()->json([
            'modules' => PermissionMatrix::forUi(),
            'scope_options' => ScopeHelper::options(),
            'role_defaults' => (object) RolePresets::defaults(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'full_name' => ['required', 'string', 'max:255'],
            'username' => ['required', 'string', 'max:100', Rule::unique('users', 'username')],
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')],
            'phone' => ['nullable', 'string', 'max:50'],
            'password' => ['nullable', 'string', 'min:6'],
            'role' => ['required', Rule::in(array_diff(User::ROLES, ['super_admin']))],
            // The permissions and access scope picked on the same form
            // (2026-10-14, by request). Without `grants` the role's preset
            // applies, as before.
            'grants' => ['sometimes', 'array'],
            'grants.*' => ['string', 'in:'.implode(',', PermissionMatrix::pairs())],
            ...ScopeHelper::rules(),
        ]);
        $grants = $validated['grants'] ?? null;
        $scope = $validated['scope'] ?? [];
        unset($validated['grants'], $validated['scope']);
        // Left blank: generate one. Either way it goes to the new user by email.
        $plainPassword = $validated['password'] ?? null ?: CredentialMailer::generatePassword();
        $validated['password'] = Hash::make($plainPassword);
        $validated['status'] = 'active';

        $user = DB::transaction(function () use ($validated, $grants, $scope) {
            $user = User::create($validated);
            $grants === null ? RolePresets::apply($user) : PermissionManager::syncGrants($user, $grants);
            ScopeHelper::saveScope($user, $scope);

            return $user;
        });
        CredentialMailer::queueWelcome('user', $user->email, $user->full_name, $user->username, $plainPassword);

        return (new UserResource($user))->response()->setStatusCode(201);
    }
}
