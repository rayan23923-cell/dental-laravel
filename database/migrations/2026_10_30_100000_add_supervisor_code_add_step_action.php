<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * "إضافة خطوة" with the supervisor code (2026-10-30, by request): clinics
 * that already picked the code's actions get the new one too, the same as
 * a clinic that never picked (every action).
 */
return new class extends Migration
{
    public function up(): void
    {
        foreach (DB::table('clinic_settings')->whereNotNull('supervisor_code_actions')->get(['id', 'supervisor_code_actions']) as $row) {
            $actions = json_decode($row->supervisor_code_actions, true);
            if (! is_array($actions) || in_array('add_step', $actions, true) || ! in_array('step', $actions, true)) {
                continue;
            }
            $actions[] = 'add_step';
            DB::table('clinic_settings')->where('id', $row->id)->update(['supervisor_code_actions' => json_encode(array_values($actions))]);
        }
    }

    public function down(): void
    {
        // Left as is.
    }
};
