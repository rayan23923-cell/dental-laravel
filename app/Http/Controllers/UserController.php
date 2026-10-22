<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Support\RolePresets;
use App\Services\CredentialMailer;
use App\Services\PermissionManager;
use App\Services\ScopeHelper;
use App\Services\UserAccountAdmin;
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
 * Editing an existing account's details and password came later
 * (2026-10-21, "إدارة المستخدمين"; rules in App\Services\UserAccountAdmin).
 * A new user's permissions and access scope are
 * picked on the same form and saved with the account; changing them later
 * is UserPermissionController's job.
 */
class UserController extends Controller
{
    public function index(Request $request): Response
    {
        UserAccountAdmin::ensureCanOpen($request->user(), 'view');

        return Inertia::render('Users/Index', [
            // super_admin accounts are listed only to another super_admin.
            'users' => User::query()
                ->when($request->user()->role !== 'super_admin', fn ($q) => $q->where('role', '!=', 'super_admin'))
                ->orderBy('full_name')
                ->get(['id', 'full_name', 'username', 'email', 'phone', 'role', 'status', 'last_login']),
        ]);
    }

    public function edit(Request $request, User $user): Response
    {
        UserAccountAdmin::ensureCanManage($request->user(), $user);

        return Inertia::render('Users/Edit', [
            'targetUser' => $user->only(['id', 'full_name', 'username', 'email', 'phone', 'role', 'status', 'notes', 'last_login', 'created_at']),
            'roles' => $user->role === 'super_admin' ? ['super_admin'] : array_values(array_diff(User::ROLES, ['super_admin'])),
            'isSelf' => $request->user()->is($user),
        ]);
    }

    public function update(Request $request, User $user): RedirectResponse
    {
        UserAccountAdmin::ensureCanManage($request->user(), $user);
        UserAccountAdmin::update($request->user(), $user, $request->validate(UserAccountAdmin::rules($user)));

        return back()->with('success', "تم حفظ بيانات {$user->full_name}.");
    }

    public function updatePassword(Request $request, User $user): RedirectResponse
    {
        UserAccountAdmin::ensureCanManage($request->user(), $user);
        $result = UserAccountAdmin::changePassword($request->user(), $user, $request->validate(UserAccountAdmin::passwordRules()));

        return back()
            ->with('success', $result['emailed'] ? 'تم تغيير كلمة المرور وإرسالها إلى بريد المستخدم.' : 'تم تغيير كلمة المرور.')
            // A generated password is shown once, so the admin can pass it on.
            ->with('generatedPassword', ($request->boolean('generate')) ? $result['password'] : null);
    }

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

        // Its permissions were set on the same form, so back to the users list.
        return redirect()->route('users.index')
            ->with('success', "تمت إضافة المستخدم {$user->full_name} مع صلاحياته.");
    }
}
