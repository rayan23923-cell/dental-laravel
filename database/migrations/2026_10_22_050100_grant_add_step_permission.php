<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Adding a step to a case became its own permission (2026-10-22, by
 * request); accounts that sign steps keep adding them.
 */
return new class extends Migration
{
    public function up(): void
    {
        $rows = DB::table('user_permissions as up')
            ->where('up.module', 'task_progress')->where('up.permission', 'track_steps')->where('up.granted', true)
            ->whereNotExists(fn ($q) => $q->from('user_permissions as own')
                ->whereColumn('own.user_id', 'up.user_id')
                ->where('own.module', 'task_progress')->where('own.permission', 'add_step'))
            ->distinct()
            ->pluck('up.user_id')
            ->map(fn ($id) => ['user_id' => $id, 'module' => 'task_progress', 'permission' => 'add_step', 'granted' => 1, 'created_at' => now()])
            ->all();

        foreach (array_chunk($rows, 500) as $chunk) {
            DB::table('user_permissions')->insert($chunk);
        }
    }

    public function down(): void
    {
        DB::table('user_permissions')->where('module', 'task_progress')->where('permission', 'add_step')->delete();
    }
};
