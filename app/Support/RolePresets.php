<?php

namespace App\Support;

use App\Models\User;
use App\Models\UserPermission;

/**
 * Ready-made grants for the desk roles (2026-10-12, by request), applied
 * when such a user is created so the account works straight away. They are
 * ordinary `user_permissions` rows: an admin can still change them on the
 * permissions screen.
 *
 *  - `reception` (موظف التذاكر): register patients and print their tickets.
 *  - `lab` (مختبري): open the lab, record results and print the lab slip.
 */
class RolePresets
{
    public const GRANTS = [
        'reception' => ['patients' => ['view', 'create']],
        'lab' => ['patient_screening' => ['view', 'confirm']],
    ];

    /** The page a desk role lands on instead of the dashboard. */
    public const HOME_ROUTES = [
        'reception' => 'patient-registrations.create',
        'lab' => 'lab.index',
    ];

    public static function apply(User $user): void
    {
        foreach (self::GRANTS[$user->role] ?? [] as $module => $permissions) {
            foreach ($permissions as $permission) {
                UserPermission::updateOrCreate(
                    ['user_id' => $user->id, 'module' => $module, 'permission' => $permission],
                    ['granted' => true],
                );
            }
        }
    }

    public static function isDeskRole(?string $role): bool
    {
        return isset(self::HOME_ROUTES[$role]);
    }
}
