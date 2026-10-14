<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Reference data is archived (soft deleted) instead of erased (2026-10-14,
 * by request), so removing an item never takes data with it; see
 * App\Support\LinkedRecords for the "still linked" guard. Dated before
 * the default-groups migration, which already queries these models.
 */
return new class extends Migration
{
    private const TABLES = [
        'education_types', 'stages', 'departments', 'case_sheet_types',
        'academic_sessions', 'groups', 'doctors', 'tasks',
    ];

    public function up(): void
    {
        foreach (self::TABLES as $table) {
            if (Schema::hasTable($table) && ! Schema::hasColumn($table, 'deleted_at')) {
                Schema::table($table, fn (Blueprint $t) => $t->softDeletes());
            }
        }
    }

    public function down(): void
    {
        foreach (self::TABLES as $table) {
            if (Schema::hasColumn($table, 'deleted_at')) {
                Schema::table($table, fn (Blueprint $t) => $t->dropSoftDeletes());
            }
        }
    }
};
