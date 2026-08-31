<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Registers the new "Advanced Periodontal Chart" case-sheet type so a task
 * can be assigned it — same table `Database\Seeders\CaseSheetTypeSeeder`
 * seeds the original 9 legacy type_codes into, but that seeder is never
 * invoked automatically (confirmed: not called from DatabaseSeeder nor any
 * deploy step), and production's `case_sheet_types` rows come from
 * `database/schema_import.sql` instead — a migration is the only thing
 * that actually runs unattended on every deploy, so this is the one
 * reliable place to add a brand-new type_code without a manual admin-UI
 * step on production.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('case_sheet_types')->insertOrIgnore([
            'type_code' => 'advanced_periodontal',
            'name_ar' => 'المخطط اللثوي المتقدم',
            'name_en' => 'Advanced Periodontal Chart',
            'icon' => 'teeth-open',
            'color' => 'warning',
            'is_active' => 1,
            'display_order' => 100,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function down(): void
    {
        DB::table('case_sheet_types')->where('type_code', 'advanced_periodontal')->delete();
    }
};
