<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * "المهام المطلوبة لكل قسم ومرحلة" on the dashboard became its own
 * permission (2026-10-24, by request). Every staff account that saw the
 * section before keeps it: all but super_admin (always allowed) and the
 * desk roles, which never had the dashboard.
 */
return new class extends Migration
{
    public function up(): void
    {
        $rows = DB::table('users')
            ->whereNotIn('role', ['super_admin', 'reception', 'lab'])
            ->whereNotExists(fn ($q) => $q->from('user_permissions as own')
                ->whereColumn('own.user_id', 'users.id')
                ->where('own.module', 'dashboard')->where('own.permission', 'tasks_by_department'))
            ->pluck('id')
            ->map(fn ($id) => ['user_id' => $id, 'module' => 'dashboard', 'permission' => 'tasks_by_department', 'granted' => 1, 'created_at' => now()])
            ->all();

        foreach (array_chunk($rows, 500) as $chunk) {
            DB::table('user_permissions')->insert($chunk);
        }
    }

    public function down(): void
    {
        DB::table('user_permissions')->where('module', 'dashboard')->where('permission', 'tasks_by_department')->delete();
    }
};
