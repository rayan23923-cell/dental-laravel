<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Support\RolePresets;
use App\Services\CredentialMailer;
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
 * not part of this pass; permission assignment for a user (new or
 * existing) is UserPermissionController's job, not duplicated here.
 */
class UserController extends Controller
{
    public function create(): Response
    {
        return Inertia::render('Users/Create', [
            'roles' => array_values(array_diff(User::ROLES, ['super_admin'])),
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
        ]);
        // Left blank: generate one. Either way it goes to the new user by email.
        $plainPassword = $validated['password'] ?? null ?: CredentialMailer::generatePassword();
        $validated['password'] = Hash::make($plainPassword);
        $validated['status'] = 'active';

        $user = User::create($validated);
        RolePresets::apply($user);
        CredentialMailer::queueWelcome('user', $user->email, $user->full_name, $user->username, $plainPassword);

        // Straight into the existing permission-grant screen for the user
        // just created, rather than a separate "user added" page — there's
        // nothing useful to show about a brand-new account except letting
        // the admin immediately set what it can do.
        return redirect()->route('permissions.edit', $user->id)
            ->with('success', 'تمت إضافة المستخدم. حدد صلاحياته أدناه.');
    }
}
