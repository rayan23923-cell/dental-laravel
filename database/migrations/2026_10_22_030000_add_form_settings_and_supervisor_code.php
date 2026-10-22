<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * "إعدادات النماذج" and the supervisor code (2026-10-22, by request); see
 * App\Support\FormSettings and App\Services\SupervisorCode.
 *
 * The new task-progress permissions split up what `start`/`finish`/`view`
 * used to cover, so accounts that had those keep doing what they did:
 *   - start or finish → track_steps (signing steps);
 *   - finish → grade (adding and editing grades);
 *   - view → view_grade, view_status.
 */
return new class extends Migration
{
    private const GRANTS = [
        'track_steps' => ['start', 'finish'],
        'grade' => ['finish'],
        'view_grade' => ['view'],
        'view_status' => ['view'],
    ];

    public function up(): void
    {
        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->boolean('electronic_forms_enabled')->default(true);
            $table->boolean('paper_forms_enabled')->default(true);
            $table->boolean('show_grades_to_doctors')->default(true);
            $table->boolean('supervisor_code_enabled')->default(false);
            $table->string('supervisor_code_period', 10)->default('daily');
            $table->json('supervisor_code_actions')->nullable();
        });

        foreach (self::GRANTS as $permission => $from) {
            $rows = DB::table('user_permissions as up')
                ->where('up.module', 'task_progress')
                ->whereIn('up.permission', $from)
                ->where('up.granted', true)
                ->whereNotExists(fn ($q) => $q->from('user_permissions as own')
                    ->whereColumn('own.user_id', 'up.user_id')
                    ->where('own.module', 'task_progress')->where('own.permission', $permission))
                ->distinct()
                ->pluck('up.user_id')
                ->map(fn ($id) => ['user_id' => $id, 'module' => 'task_progress', 'permission' => $permission, 'granted' => 1, 'created_at' => now()])
                ->all();

            foreach (array_chunk($rows, 500) as $chunk) {
                DB::table('user_permissions')->insert($chunk);
            }
        }
    }

    public function down(): void
    {
        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->dropColumn([
                'electronic_forms_enabled', 'paper_forms_enabled', 'show_grades_to_doctors',
                'supervisor_code_enabled', 'supervisor_code_period', 'supervisor_code_actions',
            ]);
        });
        DB::table('user_permissions')->where('module', 'task_progress')
            ->whereIn('permission', [...array_keys(self::GRANTS), 'supervisor_code', 'form_settings'])->delete();
    }
};
