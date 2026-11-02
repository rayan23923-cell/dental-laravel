<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Waiting screen "بانتظار الفحص" (2026-11-02, by request): when the lab
 * prints a pending patient's samples sheet ("بدء الفحص"), the time is
 * recorded so the patient shows on the waiting screen until the result
 * is recorded. Then "النتيجة جاهزة للاستلام" until the lab marks the
 * result as handed over (`lab_result_received_at`).
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('patients_simple', 'lab_sample_printed_at')) {
            Schema::table('patients_simple', function (Blueprint $table) {
                $table->dateTime('lab_sample_printed_at')->nullable();
            });
        }
        if (! Schema::hasColumn('patients_simple', 'lab_result_received_at')) {
            Schema::table('patients_simple', function (Blueprint $table) {
                $table->dateTime('lab_result_received_at')->nullable();
            });
        }
    }

    public function down(): void
    {
        foreach (['lab_sample_printed_at', 'lab_result_received_at'] as $column) {
            if (Schema::hasColumn('patients_simple', $column)) {
                Schema::table('patients_simple', fn (Blueprint $t) => $t->dropColumn($column));
            }
        }
    }
};
