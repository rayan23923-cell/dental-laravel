<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets a doctor start filling in a case sheet before formally starting the
 * task (optional prep notes — see `App\Support\CaseSheetResolver::existingDraftRecordId()`),
 * without creating a real `TaskInstance` (which would require going
 * through `TaskStarter::start()`'s mandatory `PatientScreeningGate`).
 * Nullable, no FK — matches this project's existing convention on
 * `task_instances_id`/`patient_registration_id` on these same 8 tables.
 */
return new class extends Migration
{
    private const TABLES = [
        'dental_charts',
        'prosthodontics_records',
        'complete_denture_records',
        'surgeries',
        'periodontal_charts',
        'orthodontics_records',
        'prevention_records',
        'oral_medicine_charts',
    ];

    public function up(): void
    {
        foreach (self::TABLES as $table) {
            Schema::table($table, function (Blueprint $blueprint) {
                $blueprint->integer('task_id')->nullable()->index();
            });
        }
    }

    public function down(): void
    {
        foreach (self::TABLES as $table) {
            Schema::table($table, function (Blueprint $blueprint) {
                $blueprint->dropColumn('task_id');
            });
        }
    }
};
