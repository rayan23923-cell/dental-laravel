<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * `orthodontics_records`, `prevention_records`, `oral_medicine_charts` are
 * the 3 of 8 case-sheet tables (confirmed via a fresh read of all 8
 * models, not assumed) with neither a `notes` field nor a
 * `senior_signature`-equivalent field — the other 5 already have one or
 * the other (`notes`/`senior_signature` on dental_charts/surgeries/
 * periodontal_charts, or the analogous per-stage signature/grade fields
 * on prosthodontics_records/complete_denture_records). These two new
 * columns give the 3 gapped tables the same "supervisor can edit, doctor
 * cannot" field pair the others already have one way or another — see
 * `App\Support\CaseSheetSupervisorFields`.
 */
return new class extends Migration
{
    private const TABLES = ['orthodontics_records', 'prevention_records', 'oral_medicine_charts'];

    public function up(): void
    {
        foreach (self::TABLES as $table) {
            Schema::table($table, function (Blueprint $blueprint) {
                $blueprint->text('supervisor_notes')->nullable();
                $blueprint->longText('supervisor_signature')->nullable();
            });
        }
    }

    public function down(): void
    {
        foreach (self::TABLES as $table) {
            Schema::table($table, function (Blueprint $blueprint) {
                $blueprint->dropColumn(['supervisor_notes', 'supervisor_signature']);
            });
        }
    }
};
