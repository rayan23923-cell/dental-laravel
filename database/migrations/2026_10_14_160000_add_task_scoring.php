<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Points-based requirements (2026-10-14, by request): a task can carry a
 * scoring setup (work options with points, multipliers, a points target and
 * a weight), a completed case records the work done and its points, and a
 * department carries the pass percentage. Also registers the pediatric
 * dentistry case-sheet type, which had no row. See App\Support\TaskScoring.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tasks', function (Blueprint $table) {
            $table->json('scoring')->nullable();
        });
        Schema::table('task_instances', function (Blueprint $table) {
            $table->decimal('points', 8, 2)->nullable();
            $table->json('work_items')->nullable();
        });
        Schema::table('departments', function (Blueprint $table) {
            $table->decimal('pass_percent', 5, 2)->nullable();
        });

        DB::table('case_sheet_types')->insertOrIgnore([
            'type_code' => 'pediatric',
            'name_ar' => 'طب أسنان الأطفال',
            'name_en' => 'Pediatric Dentistry',
            'icon' => 'child',
            'color' => 'info',
            'is_active' => 1,
            'display_order' => 110,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function down(): void
    {
        Schema::table('tasks', fn (Blueprint $table) => $table->dropColumn('scoring'));
        Schema::table('task_instances', fn (Blueprint $table) => $table->dropColumn(['points', 'work_items']));
        Schema::table('departments', fn (Blueprint $table) => $table->dropColumn('pass_percent'));
    }
};
