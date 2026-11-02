<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Waiting screen "بانتظار الفحص" (2026-11-02, by request): when the lab
 * prints a pending patient's samples sheet ("بدء الفحص"), the time is
 * recorded so the patient shows on the waiting screen until the result
 * is recorded.
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
    }

    public function down(): void
    {
        if (Schema::hasColumn('patients_simple', 'lab_sample_printed_at')) {
            Schema::table('patients_simple', fn (Blueprint $t) => $t->dropColumn('lab_sample_printed_at'));
        }
    }
};
