<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Same root cause as the migration right before this one (production's
 * real `clinic_system2` database predates `database/schema_import.sql` in
 * specific, narrow ways) — this time `academic_sessions.id` was missing
 * AUTO_INCREMENT (and, going by the error, very possibly its PRIMARY KEY
 * too — `schema_import.sql` adds both via separate `ALTER TABLE`
 * statements). `AcademicSessionController::store()`'s
 * `AcademicSession::create()` failed with `SQLSTATE[HY000]: 1364 Field
 * 'id' doesn't have a default value`, since Eloquent never supplies an id
 * itself — it relies entirely on the column being AUTO_INCREMENT.
 *
 * Checked via `information_schema` rather than assumed, so this is a
 * no-op (not an error) on any database where it's already correct —
 * confirmed locally it is.
 */
return new class extends Migration
{
    public function up(): void
    {
        $hasPrimaryKey = DB::table('information_schema.key_column_usage')
            ->where('table_schema', DB::connection()->getDatabaseName())
            ->where('table_name', 'academic_sessions')
            ->where('constraint_name', 'PRIMARY')
            ->exists();

        if (! $hasPrimaryKey) {
            DB::statement('ALTER TABLE `academic_sessions` ADD PRIMARY KEY (`id`)');
        }

        $column = DB::table('information_schema.columns')
            ->where('table_schema', DB::connection()->getDatabaseName())
            ->where('table_name', 'academic_sessions')
            ->where('column_name', 'id')
            ->first();

        if ($column && ! str_contains(strtolower($column->extra ?? ''), 'auto_increment')) {
            DB::statement('ALTER TABLE `academic_sessions` MODIFY `id` INT(11) NOT NULL AUTO_INCREMENT');
        }
    }

    public function down(): void
    {
        // Deliberately no-op: reverting AUTO_INCREMENT/PRIMARY KEY would
        // risk breaking every existing row's id, for a column that should
        // always have had both in the first place.
    }
};
