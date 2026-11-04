<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Refused attempts to link a patient to a case sheet (2026-11-04, by
 * request, against stolen or forged receipts): another doctor entering a
 * receipt's QR/code that is already linked to someone else's case, or a
 * patient who isn't «سليم». Shown to staff with the patient's link
 * (who, which task, when). See App\Support\CasePatientLinks.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('case_patient_link_attempts', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('patient_registration_id')->nullable()->index();
            // Who tried, and for which case.
            $table->unsignedBigInteger('doctor_id')->nullable()->index();
            $table->unsignedBigInteger('task_id')->nullable();
            // Whose case the receipt was already linked to at the time.
            $table->unsignedBigInteger('linked_doctor_id')->nullable();
            $table->unsignedBigInteger('linked_task_id')->nullable();
            // already_used | flagged | pending
            $table->string('reason', 20);
            // qr | code
            $table->string('method', 10)->nullable();
            $table->string('ip', 45)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('case_patient_link_attempts');
    }
};
