<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Two desk roles (2026-10-12, by request): `reception` (موظف التذاكر)
 * registers patients and prints their tickets, `lab` (مختبري) records
 * screening results and prints the lab slip. See App\Support\RolePresets.
 */
return new class extends Migration
{
    private const BEFORE = "'super_admin','admin','editor','doctor','accountant','senior','hr'";

    public function up(): void
    {
        if (DB::getDriverName() !== 'mysql' && DB::getDriverName() !== 'mariadb') {
            return;
        }
        DB::statement("ALTER TABLE users MODIFY role ENUM(".self::BEFORE.",'reception','lab') NOT NULL DEFAULT 'editor'");
    }

    public function down(): void
    {
        if (DB::getDriverName() !== 'mysql' && DB::getDriverName() !== 'mariadb') {
            return;
        }
        DB::table('users')->whereIn('role', ['reception', 'lab'])->update(['role' => 'editor']);
        DB::statement("ALTER TABLE users MODIFY role ENUM(".self::BEFORE.") NOT NULL DEFAULT 'editor'");
    }
};
