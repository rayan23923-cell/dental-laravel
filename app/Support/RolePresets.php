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
 *  - `accountant` (محاسب): payments, and the registration services and
 *    their prices.
 */
class RolePresets
{
    public const GRANTS = [
        // Each desk sees and prints its own income (2026-10-26, by request).
        'reception' => ['patients' => ['view', 'create'], 'payments' => ['view_tickets'], 'printer_settings' => ['view']],
        'lab' => ['patient_screening' => ['view', 'confirm'], 'payments' => ['view_lab'], 'printer_settings' => ['view']],
        // The accountant (2026-10-24, by request): payments and the
        // registration services with their prices.
        'accountant' => [
            'payments' => ['view', 'create', 'delete', 'export'],
            'register_settings' => ['view', 'edit'],
            'printer_settings' => ['view'],
        ],
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

    /**
     * Each role's ready-made grants as "module.permission" pairs, which the
     * add-user form pre-ticks when that role is picked. Roles without a
     * preset start with nothing ticked.
     */
    public static function defaults(): array
    {
        $out = [];
        foreach (self::GRANTS as $role => $modules) {
            foreach ($modules as $module => $permissions) {
                foreach ($permissions as $permission) {
                    $out[$role][] = "{$module}.{$permission}";
                }
            }
        }

        return $out;
    }

    public static function isDeskRole(?string $role): bool
    {
        return isset(self::HOME_ROUTES[$role]);
    }
}
