<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Support\RolePresets;
use App\Services\CredentialMailer;
use App\Services\PermissionManager;
use App\Services\ScopeHelper;
use App\Support\PermissionMatrix;
use Illuminate\Support\Facades\DB;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Creating a new staff/admin account — genuinely new, not a port; see
 * App\Http\Controllers\Api\UserController's docblock for why (the web app
 * never had this either, only Breeze's public self-registration screen).
 * Scoped to create/store only — editing an existing user's basic info was
 * not part of this pass. A new user's permissions and access scope are
 * picked on the same form and saved with the account; changing them later
 * is UserPermissionController's job.
 */
class UserController extends Controller
{
    public function create(): Response
    {
        $o = ScopeHelper::options();

        return Inertia::render('Users/Create', [
            'roles' => array_values(array_diff(User::ROLES, ['super_admin'])),
            // The same editor as the permissions page, filled in before the
            // account exists (2026-10-14, by request).
            'modules' => PermissionMatrix::forUi(),
            'roleDefaults' => RolePresets::defaults(),
            'scopeOptions' => [
                'departments' => $o['departments'],
                'stages' => $o['stages'],
                'educationTypes' => $o['education_types'],
                'academicSessions' => $o['academic_sessions'],
            ],
        ]);
    }

    public function store(Request $request): RedirectResponse
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

        // Its permissions were set on the same form, so back to the list.
        return redirect()->route('permissions.index')
            ->with('success', "تمت إضافة المستخدم {$user->full_name} مع صلاحياته.");
    }
}
