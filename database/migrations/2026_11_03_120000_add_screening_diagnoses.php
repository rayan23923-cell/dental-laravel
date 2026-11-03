<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * "غير سليم" diagnosis (2026-11-03, by request): when the lab marks a
 * patient "غير سليم" it picks which test came back positive (B, C, HIV,
 * one or more), stored as a JSON list and printed on the slip, the lab
 * receipt and the patient's records. See App\Support\ScreeningDiagnosis.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('patients_simple', 'screening_diagnoses')) {
            Schema::table('patients_simple', function (Blueprint $table) {
                $table->text('screening_diagnoses')->nullable();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('patients_simple', 'screening_diagnoses')) {
            Schema::table('patients_simple', fn (Blueprint $t) => $t->dropColumn('screening_diagnoses'));
        }
    }
};
