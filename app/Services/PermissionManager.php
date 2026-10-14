<?php

namespace App\Services;

use App\Models\User;
use App\Models\UserPermission;
use App\Support\PermissionMatrix;
use Illuminate\Support\Facades\Cache;

/**
 * Ports the original app's includes/PermissionManager.php +
 * permission_helper.php (two parallel implementations of the same idea in
 * the original — consolidated here into one). Confirmed live via codebase
 * research: instantiated in 14+ real pages (navbar, admin header, several
 * ajax CRUD endpoints), querying `user_permissions` — unlike `roles`/
 * `permissions`/`role_permissions`, which turned out to be an orphaned
 * parallel system nothing in real access control reads (actual role
 * gating uses the `users.role` enum, see EnsureUserHasRole middleware).
 *
 * `super_admin` bypasses every check, matching the original.
 */
class PermissionManager
{
    public function __construct(private readonly User $user)
    {
    }

    public function isSuperAdmin(): bool
    {
        return $this->user->role === 'super_admin';
    }

    public function isAdmin(): bool
    {
        return in_array($this->user->role, ['admin', 'super_admin'], true);
    }

    public function can(string $module, string $permission): bool
    {
        if ($this->isSuperAdmin()) {
            return true;
        }

        return Cache::remember(
            "user-permission:{$this->user->id}:{$module}:{$permission}",
            now()->addMinutes(5),
            fn () => UserPermission::query()
                ->where('user_id', $this->user->id)
                ->where('module', $module)
                ->where('permission', $permission)
                ->where('granted', true)
                ->exists()
        );
    }

    public function canView(string $module): bool
    {
        return $this->can($module, 'view');
    }

    public function canCreate(string $module): bool
    {
        return $this->can($module, 'create');
    }

    public function canEdit(string $module): bool
    {
        return $this->can($module, 'edit');
    }

    public function canDelete(string $module): bool
    {
        return $this->can($module, 'delete');
    }

    public function canExport(string $module): bool
    {
        return $this->can($module, 'export');
    }

    public static function forget(int $userId, string $module, string $permission): void
    {
        Cache::forget("user-permission:{$userId}:{$module}:{$permission}");
    }

    /**
     * Writes one row per matrix action for $user: granted when its
     * "module.permission" pair is in $grants, revoked otherwise. Shared by
     * the permissions screen and the add-user form (2026-10-14).
     */
    public static function syncGrants(User $user, array $grants): void
    {
        foreach (PermissionMatrix::modules() as $module => $definition) {
            foreach (array_keys($definition['permissions']) as $permission) {
                UserPermission::updateOrCreate(
                    ['user_id' => $user->id, 'module' => $module, 'permission' => $permission],
                    ['granted' => in_array("{$module}.{$permission}", $grants, true)]
                );

                self::forget($user->id, $module, $permission);
            }
        }
    }
}
