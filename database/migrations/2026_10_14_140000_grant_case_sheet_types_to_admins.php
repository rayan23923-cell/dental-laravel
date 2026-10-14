<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * "إدارة النماذج السريرية" became its own permission module (2026-10-14).
 * Every admin could open the page before, so each admin keeps that access;
 * it can be taken away per account on the permissions page.
 */
return new class extends Migration
{
    public function up(): void
    {
        $now = now();
        foreach (DB::table('users')->where('role', 'admin')->pluck('id') as $userId) {
            foreach (['view', 'create', 'edit', 'delete'] as $permission) {
                DB::table('user_permissions')->updateOrInsert(
                    ['user_id' => $userId, 'module' => 'case_sheet_types', 'permission' => $permission],
                    ['granted' => true, 'created_at' => $now, 'updated_at' => $now],
                );
            }
        }
    }

    public function down(): void
    {
        DB::table('user_permissions')->where('module', 'case_sheet_types')->delete();
    }
};
