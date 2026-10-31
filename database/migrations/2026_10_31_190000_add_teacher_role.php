<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * The teaching-staff role `teacher` (تدريسي, 2026-10-31, by request). It
 * carries no ready-made permissions: departments and what each teacher may
 * do are picked later on the permissions screen.
 */
return new class extends Migration
{
    private const BEFORE = "'super_admin','admin','editor','doctor','accountant','senior','hr','reception','lab'";

    public function up(): void
    {
        if (DB::getDriverName() !== 'mysql' && DB::getDriverName() !== 'mariadb') {
            return;
        }
        DB::statement('ALTER TABLE users MODIFY role ENUM('.self::BEFORE.",'teacher') NOT NULL DEFAULT 'editor'");
    }

    public function down(): void
    {
        if (DB::getDriverName() !== 'mysql' && DB::getDriverName() !== 'mariadb') {
            return;
        }
        DB::table('users')->where('role', 'teacher')->update(['role' => 'editor']);
        DB::statement('ALTER TABLE users MODIFY role ENUM('.self::BEFORE.") NOT NULL DEFAULT 'editor'");
    }
};
