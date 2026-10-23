<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * "إلغاء بدء المهمة" (2026-10-23, by request): a system-wide switch in the
 * general settings and its own task_progress permission, given to the
 * accounts that start tasks. See App\Services\TaskCanceller.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->boolean('task_cancel_enabled')->default(true);
        });

        $rows = DB::table('user_permissions as up')
            ->where('up.module', 'task_progress')->where('up.permission', 'start')->where('up.granted', true)
            ->whereNotExists(fn ($q) => $q->from('user_permissions as own')
                ->whereColumn('own.user_id', 'up.user_id')
                ->where('own.module', 'task_progress')->where('own.permission', 'cancel'))
            ->distinct()
            ->pluck('up.user_id')
            ->map(fn ($id) => ['user_id' => $id, 'module' => 'task_progress', 'permission' => 'cancel', 'granted' => 1, 'created_at' => now()])
            ->all();

        foreach (array_chunk($rows, 500) as $chunk) {
            DB::table('user_permissions')->insert($chunk);
        }
    }

    public function down(): void
    {
        DB::table('user_permissions')->where('module', 'task_progress')->where('permission', 'cancel')->delete();
        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->dropColumn('task_cancel_enabled');
        });
    }
};
