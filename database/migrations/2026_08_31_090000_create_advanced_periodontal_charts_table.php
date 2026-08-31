<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * "Advanced Periodontal Chart" (2026-08-31, by request) — the first
 * case-sheet resource this rebuild introduces with no counterpart in
 * dental_clinics2 at all, so unlike every other case-sheet table (all 8
 * come from database/schema_import.sql, the legacy-schema import) this one
 * needs a real Laravel migration rather than a schema import.
 *
 * Modeled functionally on periodontalchart-online.com's own charting tool
 * (32-tooth, 6-site-per-tooth probing with Mobility/Implant/Furcation/BOP/
 * Plaque/Gingival Margin/Probing Depth/Attachment Level) — see
 * App\Support\AdvancedPeriodontalChartForm and
 * resources/js/Components/AdvancedPerioChart.vue for the actual layout.
 * The big per-tooth grid lives in `chart_data` (same pattern as
 * periodontal_charts.chart_data — a plain JSON-in-longtext column, no
 * Eloquent cast, decoded/encoded by hand at the client boundary) rather
 * than 200+ individual columns.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('advanced_periodontal_charts', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('task_instances_id')->nullable()->index();
            $table->unsignedBigInteger('task_id')->nullable()->index();
            $table->unsignedBigInteger('patient_id')->nullable()->index();
            $table->unsignedBigInteger('doctor_id')->nullable()->index();

            $table->string('patient_last_name')->nullable();
            $table->string('patient_first_name')->nullable();
            $table->date('patient_dob')->nullable();
            // 'initial' | 're_evaluation' — the reference tool's own
            // "Initial Examination" / "Re-evaluation" toggle.
            $table->string('exam_type')->default('initial');
            $table->date('chart_date')->nullable();

            $table->longText('notes')->nullable();
            // Same auto-captured-signature pattern as every other case
            // sheet's `senior_signature` (App\Support\CaseSheetSignatures).
            $table->string('senior_signature')->nullable();

            // The 32-tooth grid — see this migration's own doc comment.
            $table->longText('chart_data')->nullable();

            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('advanced_periodontal_charts');
    }
};
