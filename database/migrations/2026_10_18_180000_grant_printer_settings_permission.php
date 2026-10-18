<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Printer settings became a permission (2026-10-18, by request). Every
 * account could open them before, so existing accounts keep them; an
 * admin can take them away on the permissions screen.
 */
return new class extends Migration
{
    public function up(): void
    {
        $rows = DB::table('users')
            ->where('role', '!=', 'super_admin')
            ->whereNotExists(fn ($q) => $q->from('user_permissions')
                ->whereColumn('user_permissions.user_id', 'users.id')
                ->where('module', 'printer_settings')->where('permission', 'view'))
            ->pluck('id')
            ->map(fn ($id) => ['user_id' => $id, 'module' => 'printer_settings', 'permission' => 'view', 'granted' => 1, 'created_at' => now()])
            ->all();

        foreach (array_chunk($rows, 500) as $chunk) {
            DB::table('user_permissions')->insert($chunk);
        }
    }

    public function down(): void
    {
        DB::table('user_permissions')->where('module', 'printer_settings')->delete();
    }
};
