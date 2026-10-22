<?php

namespace App\Services;

use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Editing an existing staff account's details and password (2026-10-21, by
 * request: "إدارة المستخدمين"), shared by the web page and the API so both
 * apply the same rules:
 *
 *  - only a super_admin may touch a super_admin account, and that account
 *    stays super_admin (no other role can be turned into one here, matching
 *    the add-user form);
 *  - nobody can switch their own account off or change its role;
 *  - an account switched off, or given a new password, is signed out of the
 *    apps (its API tokens are revoked) unless it is the editor's own.
 */
class UserAccountAdmin
{
    public static function rules(User $target): array
    {
        $roles = $target->role === 'super_admin' ? ['super_admin'] : array_diff(User::ROLES, ['super_admin']);

        return [
            'full_name' => ['required', 'string', 'max:255'],
            'username' => ['required', 'string', 'max:100', Rule::unique('users', 'username')->ignore($target->id)],
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')->ignore($target->id)],
            'phone' => ['nullable', 'string', 'max:20'],
            'role' => ['required', Rule::in($roles)],
            'status' => ['required', Rule::in(['active', 'inactive'])],
            'notes' => ['nullable', 'string', 'max:2000'],
        ];
    }

    public static function passwordRules(): array
    {
        return [
            // Left blank with `generate`: a new one is made and emailed.
            'password' => ['nullable', 'required_unless:generate,true', 'string', 'min:6', 'confirmed'],
            'generate' => ['sometimes', 'boolean'],
            'send_email' => ['sometimes', 'boolean'],
        ];
    }

    /**
     * The users page is where admins also reach permissions and department
     * roles since those left the menus (2026-10-22, by request), so every
     * admin may open it, like the permissions page; another account needs
     * the `users` grant.
     */
    public static function ensureCanOpen(mixed $actor, string $permission): void
    {
        abort_unless($actor instanceof User
            && ($actor->isAdmin() || (new PermissionManager($actor))->can('users', $permission)), 403);
    }

    public static function ensureCanManage(mixed $actor, User $target): void
    {
        self::ensureCanOpen($actor, 'edit');
        abort_if($target->role === 'super_admin' && $actor->role !== 'super_admin', 403);
    }

    public static function update(User $actor, User $target, array $data): User
    {
        if ($actor->is($target) && $data['status'] === 'inactive') {
            throw ValidationException::withMessages(['status' => 'لا يمكنك تعطيل حسابك أنت.']);
        }
        if ($actor->is($target) && $data['role'] !== $target->role) {
            throw ValidationException::withMessages(['role' => 'لا يمكنك تغيير دور حسابك أنت.']);
        }
        $deactivated = $target->status !== 'inactive' && $data['status'] === 'inactive';
        $target->update($data);
        if ($deactivated) {
            $target->tokens()->delete();
        }

        return $target;
    }

    /**
     * @return array{password: string, emailed: bool}
     */
    public static function changePassword(User $actor, User $target, array $data): array
    {
        $generate = (bool) ($data['generate'] ?? false);
        $plain = $generate ? CredentialMailer::generatePassword() : $data['password'];
        $target->forceFill(['password' => Hash::make($plain)])->save();
        if (! $actor->is($target)) {
            $target->tokens()->delete();
        }
        // A generated one is shown once to the admin and always emailed too.
        $emailed = ($generate || ($data['send_email'] ?? false))
            && CredentialMailer::queueWelcome('user', $target->email, $target->full_name, $target->username, $plain, reset: true);

        return ['password' => $plain, 'emailed' => $emailed];
    }
}
