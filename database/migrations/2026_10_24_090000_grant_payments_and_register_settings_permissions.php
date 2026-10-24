<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Payments and the registration services' settings became permissions
 * (2026-10-24, by request), replacing role gates. Every account the old
 * gates let in keeps its access:
 *  - payments: admin, editor and accountant accounts (the old roles);
 *  - register_settings: accounts with settings.edit (the old gate), and
 *    accountants, whose default it now is (App\Support\RolePresets).
 */
return new class extends Migration
{
    public function up(): void
    {
        $paymentUsers = DB::table('users')->whereIn('role', ['admin', 'editor', 'accountant'])->pluck('id');
        $this->grant($paymentUsers, 'payments', ['view', 'create', 'delete', 'export']);

        $settingsUsers = DB::table('user_permissions')
            ->where('module', 'settings')->where('permission', 'edit')->where('granted', true)
            ->pluck('user_id')
            ->merge(DB::table('users')->where('role', 'accountant')->pluck('id'))
            ->unique();
        $this->grant($settingsUsers, 'register_settings', ['view', 'edit']);
    }

    public function down(): void
    {
        DB::table('user_permissions')->whereIn('module', ['payments', 'register_settings'])->delete();
    }

    private function grant($userIds, string $module, array $permissions): void
    {
        $existing = DB::table('user_permissions')->where('module', $module)
            ->get(['user_id', 'permission'])
            ->map(fn ($row) => "{$row->user_id}.{$row->permission}")
            ->flip();

        $rows = [];
        foreach ($userIds as $id) {
            foreach ($permissions as $permission) {
                if (! isset($existing["{$id}.{$permission}"])) {
                    $rows[] = ['user_id' => $id, 'module' => $module, 'permission' => $permission, 'granted' => 1, 'created_at' => now()];
                }
            }
        }

        foreach (array_chunk($rows, 500) as $chunk) {
            DB::table('user_permissions')->insert($chunk);
        }
    }
};
