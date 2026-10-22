<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Task progress switched on or off for the whole system (2026-10-22, by
 * request, like the groups switch): starting and completing tasks, the
 * students' pending and completed lists, entering grades and adding steps.
 * All on, as before. See App\Support\FormSettings.
 */
return new class extends Migration
{
    private const COLUMNS = ['task_start_enabled', 'task_finish_enabled', 'task_lists_enabled', 'grade_entry_enabled', 'step_add_enabled'];

    public function up(): void
    {
        Schema::table('clinic_settings', function (Blueprint $table) {
            foreach (self::COLUMNS as $column) {
                $table->boolean($column)->default(true);
            }
        });
    }

    public function down(): void
    {
        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->dropColumn(self::COLUMNS);
        });
    }
};
