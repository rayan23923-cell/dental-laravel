<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Infectious-disease/viral-hepatitis lab screening gate — a registration
 * starts `pending` and must be marked `clear` before payment or a
 * doctor's task can proceed against it (see `PatientScreeningGate`).
 * `screening_checked_by` has no FK, same reasoning as `task_instances
 * .assigned_by`/`payments.patient_registration_id`: an additive audit
 * link, not a integrity-critical relation.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('patients_simple', function (Blueprint $table) {
            $table->enum('screening_status', ['pending', 'clear', 'flagged'])->default('pending')->after('task_id');
            $table->integer('screening_checked_by')->nullable()->after('screening_status');
            $table->timestamp('screening_checked_at')->nullable()->after('screening_checked_by');
        });
    }

    public function down(): void
    {
        Schema::table('patients_simple', function (Blueprint $table) {
            $table->dropColumn(['screening_status', 'screening_checked_by', 'screening_checked_at']);
        });
    }
};
