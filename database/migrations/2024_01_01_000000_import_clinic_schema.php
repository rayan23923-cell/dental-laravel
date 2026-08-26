<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Imports the full clinic_system2 schema (61 tables covering patients, doctors,
 * clinical charting per specialty, tasking, roles/permissions, etc.) as raw DDL
 * pulled from the source SQL dump, so the Laravel app's database matches the
 * original PHP application's structure exactly.
 */
return new class extends Migration
{
    public function up(): void
    {
        $sql = file_get_contents(database_path('schema_import.sql'));

        DB::unprepared('SET FOREIGN_KEY_CHECKS=0;');
        DB::unprepared($sql);
        DB::unprepared('SET FOREIGN_KEY_CHECKS=1;');
    }

    public function down(): void
    {
        $sql = file_get_contents(database_path('schema_import.sql'));
        preg_match_all('/CREATE TABLE `([^`]+)`/', $sql, $matches);
        $tables = array_reverse($matches[1]);

        DB::unprepared('SET FOREIGN_KEY_CHECKS=0;');
        foreach ($tables as $table) {
            DB::unprepared("DROP TABLE IF EXISTS `{$table}`");
        }
        DB::unprepared('SET FOREIGN_KEY_CHECKS=1;');
    }
};
